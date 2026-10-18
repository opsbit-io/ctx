import CTXCore
import Foundation

extension ClusterWorkspaceViewModel {
    /// Live FinOps analysis report derived from currently loaded cluster resources and live telemetry.
    /// Uses memoization to prevent main-thread stuttering during UI rendering, typing, and window resizing.
    var currentFinOpsReport: FinOpsReport {
        let podsList = resourceList(for: .pods)
        let nodesList = resourceList(for: .nodes)
        let pvcsList = resourceList(for: .storage)
        let workloadsList = resourceList(for: .workloads)

        let pods = podsList?.rows ?? []
        let nodes = nodesList?.rows ?? []
        let pvcs = pvcsList?.rows ?? []
        let workloads = workloadsList?.rows ?? []

        let customDays: Double? = {
            if finopsWindow == .custom {
                let diff = max(3600.0, finopsCustomEndDate.timeIntervalSince(finopsCustomStartDate))
                return diff / 86400.0
            }
            return nil
        }()

        let key = "\(context.id)-\(selectedNamespace.displayName)-\(finopsWindow.rawValue)-\(finopsCustomStartDate.timeIntervalSince1970)-\(finopsCustomEndDate.timeIntervalSince1970)-\(finopsAggregation.rawValue)-\(finopsPricing.providerName)-\(pods.count)-\(nodes.count)-\(pvcs.count)-\(workloads.count)-\(podsList?.loadedAt.timeIntervalSince1970 ?? 0)-\(telemetryLoadedAt?.timeIntervalSince1970 ?? 0)"

        if let verified = verifiedFinOpsReport,
           verified.window == finopsWindow,
           verified.aggregation == finopsAggregation {
            var verified = scopedVerifiedFinOpsReport(verified)
            let inventory = ClusterFinOpsEngine(pricing: finopsPricing).analyze(
                pods: pods,
                nodes: nodes,
                pvcs: pvcs,
                workloads: workloads,
                telemetry: telemetry,
                window: finopsWindow,
                customDays: customDays,
                aggregation: finopsAggregation
            )
            verified.summary.totalCoresAllocated = inventory.summary.totalCoresAllocated
            verified.summary.totalMemoryGiBAllocated = inventory.summary.totalMemoryGiBAllocated
            verified.summary.totalStorageGiBAllocated = inventory.summary.totalStorageGiBAllocated
            verified.summary.totalCoresUsed = inventory.summary.totalCoresUsed
            verified.summary.totalMemoryGiBUsed = inventory.summary.totalMemoryGiBUsed
            verified.hasLivePodTelemetry = inventory.hasLivePodTelemetry
            return verified
        }

        if let cached = cachedFinOpsReport, lastFinOpsCacheKey == key {
            return cached
        }

        let engine = ClusterFinOpsEngine(pricing: finopsPricing)
        let report = engine.analyze(
            pods: pods,
            nodes: nodes,
            pvcs: pvcs,
            workloads: workloads,
            telemetry: telemetry,
            window: finopsWindow,
            customDays: customDays,
            aggregation: finopsAggregation
        )
        cachedFinOpsReport = report
        lastFinOpsCacheKey = key
        return report
    }

    /// Whether any of the underlying inventories powering the FinOps center are currently loading.
    var isLoadingFinOps: Bool {
        isLoading(section: .pods) || isLoading(section: .nodes) || isLoading(section: .storage) || isLoading(section: .workloads) || isLoadingFinOpsProvider
    }

    /// Loads the Kubernetes inventories required to compute FinOps cost allocations.
    func loadFinOpsResources(bypassCache: Bool = false) {
        let requiredKinds: [KubernetesResourceKind] = [.pods, .nodes, .pvc, .workloads]
        for kind in requiredKinds {
            if !bypassCache, let list = resourceLists[resourceKey(kind: kind, namespace: scope(for: kind))],
               Date().timeIntervalSince(list.loadedAt) <= staleThreshold {
                continue
            }
            loadResource(kind: kind, bypassCache: bypassCache)
        }
        loadTelemetry(force: bypassCache)
        loadFinOpsCosts(bypassCache: bypassCache)
    }

    func loadFinOpsCosts(bypassCache: Bool = false) {
        let cacheKey = finopsProviderCacheKey(
            window: finopsWindow,
            aggregation: finopsAggregation,
            customStart: finopsCustomStartDate,
            customEnd: finopsCustomEndDate
        )
        if let cached = finopsProviderReportsByKey[cacheKey] {
            verifiedFinOpsReport = cached
            if !bypassCache,
               let loadedAt = finopsProviderLoadedAtByKey[cacheKey],
               Date().timeIntervalSince(loadedAt) <= 60 {
                return
            }
        } else if !bypassCache,
                  let report = verifiedFinOpsReport,
                  report.window == finopsWindow,
                  report.aggregation == finopsAggregation {
            return
        }
        finopsProviderTask?.cancel()
        isLoadingFinOpsProvider = true
        let requestID = UUID()
        finopsProviderRequestID = requestID
        let requestedWindow = finopsWindow
        let requestedAggregation = finopsAggregation
        let requestedStart = finopsCustomStartDate
        let requestedEnd = finopsCustomEndDate
        let requestedCacheKey = cacheKey
        finopsProviderTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if finopsProviderRequestID == requestID {
                    isLoadingFinOpsProvider = false
                    finopsProviderTask = nil
                    finopsProviderRequestID = nil
                }
            }
            let result = await costReader.report(
                context: context,
                window: requestedWindow,
                customStart: requestedStart,
                customEnd: requestedEnd,
                aggregation: requestedAggregation
            )
            guard !Task.isCancelled,
                  finopsProviderRequestID == requestID,
                  requestedWindow == finopsWindow,
                  requestedAggregation == finopsAggregation
            else { return }
            if let report = result.report {
                verifiedFinOpsReport = report
                finopsProviderReportsByKey[requestedCacheKey] = report
                finopsProviderLoadedAtByKey[requestedCacheKey] = Date()
            } else if finopsProviderReportsByKey[requestedCacheKey] == nil {
                verifiedFinOpsReport = nil
            }
            finopsProviderMessage = result.message
            isFinOpsProviderDetected = result.providerDetected
            cachedFinOpsReport = nil
            lastFinOpsCacheKey = ""
        }
    }

    private func finopsProviderCacheKey(
        window: FinOpsTimeWindow,
        aggregation: FinOpsAggregation,
        customStart: Date,
        customEnd: Date
    ) -> String {
        let customRange = window == .custom
            ? "-\(Int(customStart.timeIntervalSince1970))-\(Int(customEnd.timeIntervalSince1970))"
            : ""
        return "\(context.id)-\(window.rawValue)-\(aggregation.rawValue)\(customRange)"
    }

    private func scopedVerifiedFinOpsReport(_ source: FinOpsReport) -> FinOpsReport {
        guard selectedNamespace != .allNamespaces, source.aggregation != .node else { return source }
        let namespace = selectedNamespace.displayName
        let rows = source.rows.filter { row in
            if source.aggregation == .namespace {
                return row.name.caseInsensitiveCompare(namespace) == .orderedSame
            }
            return row.namespace?.caseInsensitiveCompare(namespace) == .orderedSame
        }
        let windowSpend = rows.reduce(0.0) { $0 + $1.breakdown.totalCost }
        let weightedEfficiency = rows.reduce(into: (cost: 0.0, value: 0.0)) { result, row in
            guard row.hasLiveUsage, row.breakdown.totalCost > 0 else { return }
            result.cost += row.breakdown.totalCost
            result.value += row.efficiencyScore * row.breakdown.totalCost
        }
        var summary = source.summary
        summary.windowSpendUSD = windowSpend
        summary.monthlyRunRateUSD = rows.reduce(0.0) { $0 + $1.monthlyRunRateUSD }
        summary.totalComputeCostUSD = rows.reduce(0.0) { $0 + $1.breakdown.cpuCost }
        summary.totalMemoryCostUSD = rows.reduce(0.0) { $0 + $1.breakdown.memoryCost }
        summary.totalStorageCostUSD = rows.reduce(0.0) { $0 + $1.breakdown.storageCost }
        summary.totalIdleCostUSD = 0
        summary.overallEfficiencyScore = weightedEfficiency.cost > 0
            ? weightedEfficiency.value / weightedEfficiency.cost
            : 0
        return FinOpsReport(
            window: source.window,
            aggregation: source.aggregation,
            summary: summary,
            rows: rows,
            timeSeries: [],
            recommendations: source.recommendations.filter { $0.namespace == namespace },
            dataSource: source.dataSource,
            hasLivePodTelemetry: source.hasLivePodTelemetry
        )
    }

    // MARK: - OpenCost Guided Setup & Verification Workflow

    func openOpenCostSetupWorkflow() {
        isOpenCostSetupSheetPresented = true
        openCostSetupResult = nil
        openCostSetupStepLogs = []
        runOpenCostPreflight()
    }

    func dismissOpenCostSetupWorkflow() {
        if !isInstallingOpenCost {
            openCostSetupTask?.cancel()
            openCostSetupTask = nil
            isRunningOpenCostPreflight = false
            isOpenCostSetupSheetPresented = false
        }
    }

    func runOpenCostPreflight() {
        guard !isInstallingOpenCost else { return }
        openCostSetupTask?.cancel()
        isRunningOpenCostPreflight = true
        openCostSetupResult = nil
        openCostSetupStepLogs = []

        openCostSetupTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isRunningOpenCostPreflight = false
            }
            let preflight = await openCostSetupService.runPreflight(context: context)
            guard !Task.isCancelled else { return }
            openCostPreflightReport = preflight

            let promDesc = preflight.discoveredPrometheus.map { "\($0.namespace)/\($0.serviceName):\($0.port)" } ?? "none"
            try? auditLog.record(
                AuditEvent(
                    type: .openCostPreflightChecked,
                    contextName: context.contextName,
                    message: "OpenCost preflight canProceed=\(preflight.canProceedToInstall) prometheus=\(promDesc)"
                )
            )
        }
    }

    func executeApprovedOpenCostInstall() {
        guard !isInstallingOpenCost,
              let preflight = openCostPreflightReport,
              preflight.canProceedToInstall
        else { return }

        openCostSetupTask?.cancel()
        isInstallingOpenCost = true
        openCostSetupResult = nil
        openCostSetupStepLogs = []

        let promDesc = preflight.discoveredPrometheus.map { "\($0.namespace)/\($0.serviceName):\($0.port)" } ?? "none"
        try? auditLog.record(
            AuditEvent(
                type: .openCostInstallStarted,
                contextName: context.contextName,
                message: "Approved OpenCost install started in namespace \(preflight.targetNamespace) wired to Prometheus \(promDesc)"
            )
        )

        let activeWindow = finopsWindow
        let activeAggregation = finopsAggregation
        openCostSetupTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isInstallingOpenCost = false
                openCostSetupTask = nil
            }

            let result = await openCostSetupService.installAndVerify(
                context: context,
                preflight: preflight,
                window: activeWindow,
                aggregation: activeAggregation,
                onStep: { [weak self] step in
                    Task { @MainActor [weak self] in
                        self?.openCostSetupStepLogs.append(step)
                    }
                }
            )
            guard !Task.isCancelled else { return }
            openCostSetupResult = result

            if result.success {
                try? auditLog.record(
                    AuditEvent(
                        type: .openCostInstalled,
                        contextName: context.contextName,
                        message: "OpenCost installed and verified in namespace \(preflight.targetNamespace) (\(result.verifiedReport != nil ? "API verified" : "warming up"))"
                    )
                )
                if let verified = result.verifiedReport {
                    verifiedFinOpsReport = verified
                    finopsProviderMessage = ""
                    cachedFinOpsReport = nil
                    lastFinOpsCacheKey = ""
                } else {
                    loadFinOpsCosts(bypassCache: true)
                }
                loadHelm(bypassCache: true)
                loadFinOpsResources(bypassCache: true)
            } else {
                try? auditLog.record(
                    AuditEvent(
                        type: .openCostInstallFailed,
                        contextName: context.contextName,
                        message: "OpenCost setup failed: \(result.summary)"
                    )
                )
            }
        }
    }
}
