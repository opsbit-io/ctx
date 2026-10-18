import Darwin
import Foundation

public struct KubernetesCostReadResult: Sendable, Equatable {
    public var report: FinOpsReport?
    public var message: String
    public var providerDetected: Bool

    public init(report: FinOpsReport? = nil, message: String = "", providerDetected: Bool = false) {
        self.report = report
        self.message = message
        self.providerDetected = providerDetected
    }
}

public protocol KubernetesCostReading: Sendable {
    func report(
        context: KubernetesContextProfile,
        window: FinOpsTimeWindow,
        customStart: Date,
        customEnd: Date,
        aggregation: FinOpsAggregation
    ) async -> KubernetesCostReadResult
}

/// Discovers an existing OpenCost or Kubecost Service and reads its allocation API
/// through the Kubernetes API service proxy (falling back to a short-lived local
/// port-forward when the control-plane proxy cannot dial worker node ports).
/// It never installs or modifies anything.
public final class KubernetesCostReader: KubernetesCostReading {
    private struct CostService: Sendable {
        enum Provider: String, Sendable { case openCost, kubecost }
        let provider: Provider
        let namespace: String
        let name: String
        let port: Int

        var allocationPath: String {
            provider == .kubecost && port == 9090 ? "model/allocation" : "allocation"
        }
    }

    private let kubectl: any KubectlRunning & KubectlCommandBuilding
    private let processStarter: (any KubectlProcessStarting)?
    private let timeout: TimeInterval

    public init(
        kubectl: any KubectlRunning & KubectlCommandBuilding = KubectlRunner(),
        processStarter: (any KubectlProcessStarting)? = KubectlRunner(),
        timeout: TimeInterval = 12
    ) {
        self.kubectl = kubectl
        self.processStarter = processStarter
        self.timeout = timeout
    }

    public func report(
        context: KubernetesContextProfile,
        window: FinOpsTimeWindow,
        customStart: Date,
        customEnd: Date,
        aggregation: FinOpsAggregation
    ) async -> KubernetesCostReadResult {
        var providerDetected = false
        do {
            try Task.checkCancellation()
            guard let service = try await discoverService(context: context) else {
                return KubernetesCostReadResult(
                    message: "No OpenCost or Kubecost service detected in this cluster. Showing live Kubernetes resource allocations & telemetry."
                )
            }
            providerDetected = true
            try Task.checkCancellation()

            let windowValue = Self.windowValue(window, customStart: customStart, customEnd: customEnd)
            let step = window == .h24 ? "1h" : "1d"
            let aggregate: String
            switch aggregation {
            case .namespace: aggregate = "namespace"
            case .workload: aggregate = "controller"
            case .node: aggregate = "node"
            }
            var components = URLComponents()
            components.queryItems = [
                URLQueryItem(name: "window", value: windowValue),
                URLQueryItem(name: "aggregate", value: aggregate),
                URLQueryItem(name: "accumulate", value: "false"),
                URLQueryItem(name: "step", value: step)
            ]
            let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
            let queryTimeout: TimeInterval = window == .h24 ? 12 : 25
            var output: String
            var effectiveWindow = window
            var effectiveDays: Double? = window == .custom ? max(1, customEnd.timeIntervalSince(customStart) / 86_400) : nil
            var noticeMessage: String? = nil

            do {
                output = try await fetchAllocationPayload(
                    context: context,
                    service: service,
                    query: query,
                    queryTimeout: queryTimeout
                )
            } catch {
                if window != .h24 {
                    // Graceful fast fallback to 24h window if multi-day Prometheus query times out
                    let fallbackQuery = "?window=24h&aggregate=\(aggregate)&accumulate=false&step=1h"
                    if let fallbackOutput = try? await fetchAllocationPayload(
                        context: context,
                        service: service,
                        query: fallbackQuery,
                        queryTimeout: 10
                    ) {
                        output = fallbackOutput
                        effectiveWindow = .h24
                        effectiveDays = nil
                        noticeMessage = "Displaying last 24h cost metrics (the \(window.displayName) Prometheus query timed out)."
                    } else {
                        throw error
                    }
                } else {
                    throw error
                }
            }

            let source: FinOpsDataSourceStatus = service.provider == .openCost
                ? .openCostAgent(endpoint: "\(service.namespace)/\(service.name):\(service.port)", version: "")
                : .kubecostAgent(endpoint: "\(service.namespace)/\(service.name):\(service.port)")
            guard let report = Self.parseAllocationPayload(
                output,
                window: effectiveWindow,
                customDays: effectiveDays,
                aggregation: aggregation,
                dataSource: source
            ) else {
                return KubernetesCostReadResult(
                    message: "OpenCost is installed and reachable, but it returned no allocation data for this window.",
                    providerDetected: true
                )
            }
            return KubernetesCostReadResult(report: report, message: noticeMessage ?? "", providerDetected: true)
        } catch {
            return KubernetesCostReadResult(
                message: providerDetected
                    ? "OpenCost was detected, but CTX could not reach its allocation API: \(error.localizedDescription)"
                    : "No OpenCost or Kubecost service detected in this cluster. Showing live Kubernetes resource allocations & telemetry.",
                providerDetected: providerDetected
            )
        }
    }

    private func fetchAllocationPayload(
        context: KubernetesContextProfile,
        service: CostService,
        query: String,
        queryTimeout: TimeInterval? = nil
    ) async throws -> String {
        let proxyPath = "/api/v1/namespaces/\(service.namespace)/services/\(service.name):\(service.port)/proxy/\(service.allocationPath)\(query)"
        // Prefer an explicit loopback tunnel. API-server Service proxy requests can wait for their
        // full timeout when a private control plane cannot dial Pod CIDRs, while kubectl
        // port-forward uses the already-authorized Kubernetes streaming connection.
        if let processStarter {
            let tunnelFallback = NSError(
                domain: "KubernetesCostReader",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The local OpenCost tunnel did not become ready."]
            )
            do {
                return try await fetchViaEphemeralPortForward(
                    context: context,
                    service: service,
                    query: query,
                    processStarter: processStarter,
                    fallbackError: tunnelFallback,
                    allocationTimeout: queryTimeout
                )
            } catch let error as NSError where error.domain == "KubernetesCostReader.Allocation" {
                // The tunnel worked and OpenCost accepted or processed the query. Do not submit the
                // same query again through Service proxy after an allocation timeout or error.
                throw error
            } catch {
                // Preserve compatibility with environments that disable port-forward but permit
                // API-server Service proxy access.
            }
        }
        return try await run(
            context: context,
            arguments: ["get", "--raw", proxyPath],
            timeoutOverride: min(queryTimeout ?? timeout, 6)
        )
    }

    private func fetchViaEphemeralPortForward(
        context: KubernetesContextProfile,
        service: CostService,
        query: String,
        processStarter: any KubectlProcessStarting,
        fallbackError: Error,
        allocationTimeout: TimeInterval? = nil
    ) async throws -> String {
        guard let localPort = Self.allocateEphemeralLoopbackPort() else {
            throw fallbackError
        }
        var command = try kubectl.inspectionCommand(
            context: context.contextName,
            arguments: context.kubeconfigArguments + [
                "port-forward",
                "service/\(service.name)",
                "--namespace", service.namespace,
                "\(localPort):\(service.port)",
                "--address", "127.0.0.1"
            ]
        )
        command.environmentOverrides = context.kubeconfigEnvironment
        let handle = try processStarter.start(command)
        defer { handle.terminate() }

        guard let url = URL(string: "http://127.0.0.1:\(localPort)/\(service.allocationPath)\(query)"),
              let healthURL = URL(string: "http://127.0.0.1:\(localPort)/healthz")
        else {
            throw fallbackError
        }

        // Wait until the local port-forward tunnel starts listening
        let deadline = Date().addingTimeInterval(min(timeout, 3))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var tunnelReady = false
        while Date() < deadline {
            try Task.checkCancellation()
            guard handle.isRunning else {
                let exitMsg = handle.outputIfExited().trimmingCharacters(in: .whitespacesAndNewlines)
                if !exitMsg.isEmpty {
                    throw NSError(
                        domain: "KubernetesCostReader",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: exitMsg]
                    )
                }
                throw fallbackError
            }

            var readinessRequest = URLRequest(url: healthURL)
            readinessRequest.timeoutInterval = 1
            do {
                _ = try await session.data(for: readinessRequest)
                tunnelReady = true
                break
            } catch {
                try Task.checkCancellation()
            }

            try await Task.sleep(nanoseconds: 80_000_000)
        }
        guard tunnelReady else { throw fallbackError }

        // Allocation query with dedicated non-blocking timeout
        let queryTimeout: TimeInterval = allocationTimeout ?? (timeout > 0 ? timeout : 12)
        var request = URLRequest(url: url)
        request.timeoutInterval = queryTimeout
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(
                    domain: "KubernetesCostReader.Allocation",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "OpenCost returned a non-HTTP response."]
                )
            }
            guard (200..<300).contains(http.statusCode) else {
                throw NSError(
                    domain: "KubernetesCostReader.Allocation",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "OpenCost returned HTTP \(http.statusCode)."]
                )
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(
                    domain: "KubernetesCostReader.Allocation",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "OpenCost returned an invalid UTF-8 payload."]
                )
            }
            return text
        } catch let err as NSError where err.domain == "KubernetesCostReader.Allocation" {
            throw err
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw NSError(
                domain: "KubernetesCostReader.Allocation",
                code: URLError.timedOut.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "OpenCost took longer than \(Int(queryTimeout))s to compute allocation."]
            )
        } catch {
            throw NSError(
                domain: "KubernetesCostReader.Allocation",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "OpenCost query failed: \(error.localizedDescription)"]
            )
        }
    }

    private static func allocateEphemeralLoopbackPort() -> Int? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        var boundAddr = addr
        let bindResult = withUnsafePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.bind(sock, saPtr, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        guard bindResult == 0 else { return nil }

        var actualAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let nameResult = withUnsafeMutablePointer(to: &actualAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.getsockname(sock, saPtr, &len)
            }
        }
        guard nameResult == 0 else { return nil }
        let port = Int(UInt16(bigEndian: actualAddr.sin_port))
        return port > 0 ? port : nil
    }

    public static func parseAllocationPayload(
        _ jsonString: String,
        window: FinOpsTimeWindow,
        customDays: Double? = nil,
        aggregation: FinOpsAggregation,
        dataSource: FinOpsDataSourceStatus
    ) -> FinOpsReport? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawData = root["data"]
        else { return nil }

        let sets: [[String: Any]]
        if let directSets = rawData as? [[String: Any]] {
            sets = directSets
        } else if let nested = rawData as? [[[String: Any]]] {
            sets = nested.flatMap { $0 }
        } else if let object = rawData as? [String: Any],
                  let allocations = object["sets"] as? [[String: Any]] {
            sets = allocations.compactMap { $0["allocations"] as? [String: Any] }
        } else {
            return nil
        }

        struct Bucket {
            var cpu = 0.0
            var memory = 0.0
            var storage = 0.0
            var network = 0.0
            var total = 0.0
            var weightedEfficiency = 0.0
            var efficiencyWeight = 0.0
            var hasLiveUsage = false
            var cpuCoreUsage = 0.0
            var ramByteUsage = 0.0
            var cpuCoreRequest = 0.0
            var ramByteRequest = 0.0
            var namespace: String?
        }

        var accumulated: [String: Bucket] = [:]
        var timeSeries: [FinOpsTimeSeriesPoint] = []
        let iso = ISO8601DateFormatter()
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = window == .h24 ? "HH:mm" : "MMM d"

        for set in sets {
            var bucketDate: Date?
            var bucketCompute = 0.0
            var bucketMemory = 0.0
            var bucketStorage = 0.0
            var bucketTotal = 0.0

            for (rawName, rawAllocation) in set {
                guard let allocation = rawAllocation as? [String: Any] else { continue }
                let name = (allocation["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? rawName
                let cpu = number(allocation["cpuCost"]) + number(allocation["gpuCost"])
                let memory = number(allocation["ramCost"] ?? allocation["memoryCost"])
                let storage = number(allocation["pvCost"] ?? allocation["storageCost"])
                let network = number(allocation["networkCost"]) + number(allocation["loadBalancerCost"])
                let shared = number(allocation["sharedCost"]) + number(allocation["externalCost"])
                let explicitTotal = allocation["totalCost"].map(number)
                let total = explicitTotal ?? (cpu + memory + storage + network + shared)

                if bucketDate == nil,
                   let windowDict = allocation["window"] as? [String: Any],
                   let start = windowDict["start"] as? String {
                    bucketDate = iso.date(from: start)
                }

                bucketCompute += cpu
                bucketMemory += memory
                bucketStorage += storage
                bucketTotal += total

                var current = accumulated[name] ?? Bucket()
                if current.namespace == nil,
                   let properties = allocation["properties"] as? [String: Any] {
                    current.namespace = properties["namespace"] as? String
                }
                current.cpu += cpu
                current.memory += memory
                current.storage += storage
                current.network += network
                current.total += total

                let efficiency = number(allocation["totalEfficiency"])
                if efficiency > 0, total > 0 {
                    current.weightedEfficiency += efficiency * total
                    current.efficiencyWeight += total
                    current.hasLiveUsage = true
                }
                if let cpuUsage = allocation["cpuCoreUsageAverage"] {
                    current.cpuCoreUsage += number(cpuUsage)
                    current.hasLiveUsage = true
                }
                if let ramUsage = allocation["ramByteUsageAverage"] {
                    current.ramByteUsage += number(ramUsage)
                    current.hasLiveUsage = true
                }
                if let cpuReq = allocation["cpuCoreRequestAverage"] ?? allocation["cpuCores"] {
                    current.cpuCoreRequest += number(cpuReq)
                }
                if let ramReq = allocation["ramByteRequestAverage"] ?? allocation["ramBytes"] {
                    current.ramByteRequest += number(ramReq)
                }
                accumulated[name] = current
            }

            if let date = bucketDate, bucketTotal > 0 {
                timeSeries.append(
                    FinOpsTimeSeriesPoint(
                        date: date,
                        label: labelFormatter.string(from: date),
                        totalCost: bucketTotal,
                        costByCategory: [
                            "Compute": bucketCompute,
                            "Memory": bucketMemory,
                            "Storage": bucketStorage
                        ]
                    )
                )
            }
        }

        let idleKeys = accumulated.keys.filter { $0 == "__idle__" || $0.hasPrefix("__idle__/") }
        let idle = idleKeys.reduce(0.0) { $0 + (accumulated[$1]?.total ?? 0) }
        idleKeys.forEach { accumulated.removeValue(forKey: $0) }
        accumulated.removeValue(forKey: "__unallocated__")

        let days = max(1, window == .custom ? (customDays ?? 7) : window.daysFactor)
        let monthlyFactor = 30.0 / days
        let totalAllocated = accumulated.values.reduce(0.0) { $0 + $1.total }
        let totalWindowSpend = totalAllocated + idle
        guard !accumulated.isEmpty || totalWindowSpend > 0 else { return nil }
        let efficiencyTotals = accumulated.values.reduce(into: (weighted: 0.0, weight: 0.0)) { result, bucket in
            result.weighted += bucket.weightedEfficiency
            result.weight += bucket.efficiencyWeight
        }

        let kindLabel: String
        switch aggregation {
        case .namespace: kindLabel = "Namespace"
        case .workload: kindLabel = "Workload"
        case .node: kindLabel = "Node"
        }

        let rows = accumulated.map { name, bucket -> FinOpsAllocationRow in
            let breakdown = FinOpsCostBreakdown(
                cpuCost: bucket.cpu,
                memoryCost: bucket.memory,
                storageCost: bucket.storage,
                networkCost: bucket.network
            )
            return FinOpsAllocationRow(
                id: "\(aggregation.rawValue)-\(name)",
                name: name,
                namespace: aggregation == .namespace ? name : bucket.namespace,
                breakdown: breakdown,
                efficiencyScore: bucket.efficiencyWeight > 0
                    ? min(1, max(0, bucket.weightedEfficiency / bucket.efficiencyWeight))
                    : 0,
                estimatedWasteUSD: 0,
                monthlyRunRateUSD: bucket.total * monthlyFactor,
                resourceKind: kindLabel,
                hasLiveUsage: bucket.hasLiveUsage,
                cpuCoresRequested: bucket.cpuCoreRequest,
                cpuCoresUsed: bucket.cpuCoreUsage,
                memoryGiBRequested: bucket.ramByteRequest / (1024.0 * 1024.0 * 1024.0),
                memoryGiBUsed: bucket.ramByteUsage / (1024.0 * 1024.0 * 1024.0),
                storageGiB: 0
            )
        }
        .sorted { $0.breakdown.totalCost > $1.breakdown.totalCost }

        let summary = FinOpsSummary(
            windowSpendUSD: totalWindowSpend,
            monthlyRunRateUSD: totalWindowSpend * monthlyFactor,
            potentialMonthlySavingsUSD: 0,
            overallEfficiencyScore: efficiencyTotals.weight > 0
                ? min(1, max(0, efficiencyTotals.weighted / efficiencyTotals.weight))
                : 0,
            totalCoresAllocated: rows.reduce(0.0) { $0 + $1.cpuCoresRequested },
            totalMemoryGiBAllocated: rows.reduce(0.0) { $0 + $1.memoryGiBRequested },
            totalStorageGiBAllocated: 0,
            totalCoresUsed: rows.reduce(0.0) { $0 + $1.cpuCoresUsed },
            totalMemoryGiBUsed: rows.reduce(0.0) { $0 + $1.memoryGiBUsed },
            totalIdleCostUSD: idle,
            totalComputeCostUSD: accumulated.values.reduce(0) { $0 + $1.cpu },
            totalMemoryCostUSD: accumulated.values.reduce(0) { $0 + $1.memory },
            totalStorageCostUSD: accumulated.values.reduce(0) { $0 + $1.storage }
        )
        return FinOpsReport(
            window: window,
            aggregation: aggregation,
            summary: summary,
            rows: rows,
            timeSeries: timeSeries.sorted { $0.date < $1.date },
            recommendations: [],
            dataSource: dataSource,
            hasLivePodTelemetry: false
        )
    }

    private func discoverService(context: KubernetesContextProfile) async throws -> CostService? {
        // Fast path: Check common namespaces where OpenCost and Kubecost are typically deployed
        let candidateNamespaces = ["opencost", "kubecost", "monitoring", context.namespace].filter { !$0.isEmpty }
        var deduplicatedCandidates: [String] = []
        for ns in candidateNamespaces {
            if !deduplicatedCandidates.contains(ns) {
                deduplicatedCandidates.append(ns)
            }
        }
        for ns in deduplicatedCandidates {
            if let specificOutput = try? await run(context: context, arguments: ["get", "services", "-n", ns, "--output=json"], timeoutOverride: 3) {
                if let service = parseServicesJSON(specificOutput) {
                    return service
                }
            }
        }
        // Fallback: If not found in candidate namespaces, check across the cluster if permitted
        if let allOutput = try? await run(context: context, arguments: ["get", "services", "--all-namespaces", "--output=json"], timeoutOverride: min(timeout, 5)) {
            if let service = parseServicesJSON(allOutput) {
                return service
            }
        }
        return nil
    }

    private func parseServicesJSON(_ output: String) -> CostService? {
        guard
            let data = output.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["items"] as? [[String: Any]]
        else { return nil }

        var matches: [CostService] = []
        for item in items {
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            let labels = metadata["labels"] as? [String: Any] ?? [:]
            let name = metadata["name"] as? String ?? ""
            let namespace = metadata["namespace"] as? String ?? ""
            guard !name.isEmpty, !namespace.isEmpty else { continue }
            let identity = ([name] + ["app.kubernetes.io/name", "app", "app.kubernetes.io/instance"].compactMap { labels[$0] as? String })
                .joined(separator: " ").lowercased()
            let provider: CostService.Provider?
            if identity.contains("opencost") {
                provider = .openCost
            } else if identity.contains("kubecost") || identity.contains("cost-analyzer") {
                provider = .kubecost
            } else {
                provider = nil
            }
            guard let provider else { continue }
            let spec = item["spec"] as? [String: Any] ?? [:]
            let ports = spec["ports"] as? [[String: Any]] ?? []
            let preferred = provider == .openCost ? 9003 : 9090
            let port = ports.first { Self.portNumber($0["port"]) == preferred || Self.portNumber($0["targetPort"]) == preferred }
                ?? ports.first { Self.portNumber($0["port"]) == 9003 || Self.portNumber($0["targetPort"]) == 9003 }
            guard let portNumber = port.flatMap({ Self.portNumber($0["port"]) }) else { continue }
            matches.append(CostService(provider: provider, namespace: namespace, name: name, port: portNumber))
        }
        return matches.sorted { lhs, rhs in
            let lhsRank = Self.rank(lhs)
            let rhsRank = Self.rank(rhs)
            return lhsRank == rhsRank ? lhs.name < rhs.name : lhsRank < rhsRank
        }.first
    }

    private func run(
        context: KubernetesContextProfile,
        arguments: [String],
        timeoutOverride: TimeInterval? = nil
    ) async throws -> String {
        var command = try kubectl.inspectionCommand(
            context: context.contextName,
            arguments: context.kubeconfigArguments + arguments
        )
        command.environmentOverrides = context.kubeconfigEnvironment
        let result = try await kubectl.run(command, timeout: timeoutOverride ?? timeout)
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = !stderr.isEmpty
                ? stderr
                : (result.timedOut ? "kubectl timed out while contacting the cost service." : "kubectl exited with status \(result.exitCode).")
            throw NSError(
                domain: "KubernetesCostReader",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: detail]
            )
        }
        return result.stdout
    }

    private static func windowValue(_ window: FinOpsTimeWindow, customStart: Date, customEnd: Date) -> String {
        switch window {
        case .h24: return "24h"
        case .d7: return "7d"
        case .d30: return "30d"
        case .monthToDate: return "month"
        case .custom:
            let formatter = ISO8601DateFormatter()
            return "\(formatter.string(from: customStart)),\(formatter.string(from: customEnd))"
        }
    }

    private static func portNumber(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    private static func number(_ raw: Any?) -> Double {
        if let value = raw as? Double { return value.isFinite ? value : 0 }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue.isFinite ? value.doubleValue : 0 }
        if let value = raw as? String, let parsed = Double(value), parsed.isFinite { return parsed }
        return 0
    }

    private static func rank(_ service: CostService) -> Int {
        switch service.provider {
        case .openCost:
            return service.name == "opencost" ? 0 : 1
        case .kubecost:
            if service.name.contains("cost-analyzer") { return 2 }
            if service.name.contains("kubecost-frontend") { return 3 }
            return 4
        }
    }
}
