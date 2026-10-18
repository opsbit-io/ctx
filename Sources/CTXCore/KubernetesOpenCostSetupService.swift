import Foundation

public enum OpenCostCheckStatus: String, Codable, Equatable, Sendable {
    case passed
    case warning
    case failed
}

public struct OpenCostPreflightCheck: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var status: OpenCostCheckStatus
    public var detail: String
    public var remediation: String?

    public init(
        id: String,
        title: String,
        status: OpenCostCheckStatus,
        detail: String,
        remediation: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.remediation = remediation
    }
}

public struct DiscoveredPrometheusEndpoint: Equatable, Sendable {
    public var namespace: String
    public var serviceName: String
    public var port: Int
    public var hasReadyEndpoints: Bool

    public init(
        namespace: String,
        serviceName: String,
        port: Int,
        hasReadyEndpoints: Bool
    ) {
        self.namespace = namespace
        self.serviceName = serviceName
        self.port = port
        self.hasReadyEndpoints = hasReadyEndpoints
    }

    public var inClusterURL: String {
        "http://\(serviceName).\(namespace).svc:\(port)"
    }
}

public struct DiscoveredStorageClassInfo: Equatable, Sendable {
    public var classes: [String]
    public var defaultClasses: [String]
    public var summary: String

    public init(
        classes: [String] = [],
        defaultClasses: [String] = [],
        summary: String = ""
    ) {
        self.classes = classes
        self.defaultClasses = defaultClasses
        self.summary = summary
    }
}

public struct OpenCostPlannedResource: Identifiable, Equatable, Sendable {
    public var id: String { "\(kind)/\(namespace ?? "cluster")/\(name)" }
    public var kind: String
    public var name: String
    public var namespace: String?
    public var summary: String

    public init(kind: String, name: String, namespace: String? = nil, summary: String) {
        self.kind = kind
        self.name = name
        self.namespace = namespace
        self.summary = summary
    }
}

public struct OpenCostSetupPreflightReport: Equatable, Sendable {
    public var contextName: String
    public var clusterName: String
    public var isProduction: Bool
    public var targetNamespace: String
    public var releaseName: String
    public var chartRepositoryURL: String
    public var chartReference: String
    public var helmExecutablePath: String?
    public var helmVersion: String?
    public var chartVersion: String?
    public var appVersion: String?
    public var containerImage: String?
    public var serverDryRunVerified: Bool
    public var renderedManifestYAML: String?
    public var existingProviderEndpoint: String?
    public var discoveredPrometheus: DiscoveredPrometheusEndpoint?
    public var storageClassInfo: DiscoveredStorageClassInfo
    public var checks: [OpenCostPreflightCheck]
    public var plannedResources: [OpenCostPlannedResource]
    public var commandArgumentsPreview: [[String]]
    public var canProceedToInstall: Bool
    public var remediationSummary: String?

    public init(
        contextName: String,
        clusterName: String,
        isProduction: Bool,
        targetNamespace: String = "opencost",
        releaseName: String = "opencost",
        chartRepositoryURL: String = "https://opencost.github.io/opencost-helm-chart",
        chartReference: String = "opencost-charts/opencost",
        helmExecutablePath: String? = nil,
        helmVersion: String? = nil,
        chartVersion: String? = nil,
        appVersion: String? = nil,
        containerImage: String? = nil,
        serverDryRunVerified: Bool = false,
        renderedManifestYAML: String? = nil,
        existingProviderEndpoint: String? = nil,
        discoveredPrometheus: DiscoveredPrometheusEndpoint? = nil,
        storageClassInfo: DiscoveredStorageClassInfo = DiscoveredStorageClassInfo(),
        checks: [OpenCostPreflightCheck] = [],
        plannedResources: [OpenCostPlannedResource] = [],
        commandArgumentsPreview: [[String]] = [],
        canProceedToInstall: Bool = false,
        remediationSummary: String? = nil
    ) {
        self.contextName = contextName
        self.clusterName = clusterName
        self.isProduction = isProduction
        self.targetNamespace = targetNamespace
        self.releaseName = releaseName
        self.chartRepositoryURL = chartRepositoryURL
        self.chartReference = chartReference
        self.helmExecutablePath = helmExecutablePath
        self.helmVersion = helmVersion
        self.chartVersion = chartVersion
        self.appVersion = appVersion
        self.containerImage = containerImage
        self.serverDryRunVerified = serverDryRunVerified
        self.renderedManifestYAML = renderedManifestYAML
        self.existingProviderEndpoint = existingProviderEndpoint
        self.discoveredPrometheus = discoveredPrometheus
        self.storageClassInfo = storageClassInfo
        self.checks = checks
        self.plannedResources = plannedResources
        self.commandArgumentsPreview = commandArgumentsPreview
        self.canProceedToInstall = canProceedToInstall
        self.remediationSummary = remediationSummary
    }

    public var formattedCommandPreview: String {
        commandArgumentsPreview
            .map { args in
                args.map { arg in
                    arg.contains(" ") ? "\"\(arg)\"" : arg
                }.joined(separator: " ")
            }
            .joined(separator: "\n")
    }
}

public struct OpenCostSetupStepLog: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var step: String
    public var status: OpenCostCheckStatus
    public var detail: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        step: String,
        status: OpenCostCheckStatus,
        detail: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.step = step
        self.status = status
        self.detail = detail
    }
}

public struct OpenCostSetupExecutionResult: Equatable, Sendable {
    public var success: Bool
    public var summary: String
    public var steps: [OpenCostSetupStepLog]
    public var verifiedReport: FinOpsReport?
    public var remediation: String?

    public init(
        success: Bool,
        summary: String,
        steps: [OpenCostSetupStepLog],
        verifiedReport: FinOpsReport? = nil,
        remediation: String? = nil
    ) {
        self.success = success
        self.summary = summary
        self.steps = steps
        self.verifiedReport = verifiedReport
        self.remediation = remediation
    }
}

public protocol KubernetesOpenCostSettingUp: Sendable {
    func runPreflight(context: KubernetesContextProfile) async -> OpenCostSetupPreflightReport
    func installAndVerify(
        context: KubernetesContextProfile,
        preflight: OpenCostSetupPreflightReport,
        window: FinOpsTimeWindow,
        aggregation: FinOpsAggregation,
        onStep: @Sendable (OpenCostSetupStepLog) -> Void
    ) async -> OpenCostSetupExecutionResult
}

public final class KubernetesOpenCostSetupService: KubernetesOpenCostSettingUp {
    public static let chartRepositoryName = "opencost-charts"
    public static let chartRepositoryURL = "https://opencost.github.io/opencost-helm-chart"
    public static let chartReference = "opencost-charts/opencost"
    public static let targetNamespace = "opencost"
    public static let releaseName = "opencost"

    private let runner: any KubectlRunning & KubectlCommandBuilding
    private let costReader: any KubernetesCostReading
    private let helmPathResolver: @Sendable () -> String?
    private let timeout: TimeInterval

    public init(
        runner: any KubectlRunning & KubectlCommandBuilding = KubectlRunner(),
        costReader: any KubernetesCostReading = KubernetesCostReader(),
        helmPathResolver: @escaping @Sendable () -> String? = { KubectlRunner().resolve("helm") },
        timeout: TimeInterval = 45
    ) {
        self.runner = runner
        self.costReader = costReader
        self.helmPathResolver = helmPathResolver
        self.timeout = timeout
    }

    public func runPreflight(context: KubernetesContextProfile) async -> OpenCostSetupPreflightReport {
        var checks: [OpenCostPreflightCheck] = []
        let isProduction = context.environmentType == .production
        let rawCluster = context.clusterName.isEmpty ? context.contextName : context.clusterName
        let clusterName = Self.sanitizedClusterIdentifier(from: rawCluster)

        // 1. Verify Helm CLI availability & version
        let helmPath = helmPathResolver()
        var helmVersion: String?
        if let helmPath {
            let versionResult = try? await runHelm(
                helmPath: helmPath,
                context: context,
                arguments: ["version", "--short"],
                includeContextFlags: false,
                timeout: 10
            )
            if let versionResult, versionResult.exitCode == 0 {
                let cleaned = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                helmVersion = cleaned.isEmpty ? "Detected" : cleaned
                checks.append(
                    OpenCostPreflightCheck(
                        id: "cli-helm",
                        title: "Helm CLI binary",
                        status: .passed,
                        detail: "Found \(helmPath) (\(helmVersion ?? "ready"))."
                    )
                )
            } else {
                checks.append(
                    OpenCostPreflightCheck(
                        id: "cli-helm",
                        title: "Helm CLI binary",
                        status: .failed,
                        detail: "Helm binary at \(helmPath) could not execute `helm version --short`.",
                        remediation: "Verify your local Helm installation (`brew install helm` or `helm version`)."
                    )
                )
            }
        } else {
            checks.append(
                OpenCostPreflightCheck(
                    id: "cli-helm",
                    title: "Helm CLI binary",
                    status: .failed,
                    detail: "Helm was not found in PATH or standard CLI directories.",
                    remediation: "Install Helm (`brew install helm`) and reopen CTX before setting up OpenCost."
                )
            )
        }

        // 2. Verify RBAC permissions via `kubectl auth can-i`
        let requiredPermissions: [(label: String, args: [String])] = [
            ("create namespaces", ["auth", "can-i", "create", "namespaces"]),
            ("create serviceaccounts (-n opencost)", ["auth", "can-i", "create", "serviceaccounts", "-n", Self.targetNamespace]),
            ("create deployments (-n opencost)", ["auth", "can-i", "create", "deployments", "-n", Self.targetNamespace]),
            ("create services (-n opencost)", ["auth", "can-i", "create", "services", "-n", Self.targetNamespace]),
            ("create clusterroles", ["auth", "can-i", "create", "clusterroles"]),
            ("create clusterrolebindings", ["auth", "can-i", "create", "clusterrolebindings"])
        ]

        var missingPermissions: [String] = []
        var rbacConnectionError: String?
        for check in requiredPermissions {
            do {
                let result = try await runKubectlResult(context: context, arguments: check.args, timeout: 12)
                let answer = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if result.exitCode != 0 || answer != "yes" {
                    let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if answer != "no", !stderr.isEmpty, !stderr.lowercased().contains("warning:") {
                        rbacConnectionError = stderr
                        break
                    }
                    missingPermissions.append(check.label)
                }
            } catch {
                rbacConnectionError = error.localizedDescription
                break
            }
        }

        if let rbacConnectionError {
            checks.append(
                OpenCostPreflightCheck(
                    id: "rbac-permissions",
                    title: "Cluster reachability & RBAC",
                    status: .failed,
                    detail: "Could not verify cluster RBAC permissions: \(rbacConnectionError)",
                    remediation: "Authenticate to \(context.contextName) and verify `kubectl cluster-info` succeeds."
                )
            )
        } else if missingPermissions.isEmpty {
            checks.append(
                OpenCostPreflightCheck(
                    id: "rbac-permissions",
                    title: "Cluster & namespace RBAC permissions",
                    status: .passed,
                    detail: "Verified permissions to create Namespace, ServiceAccount, ClusterRole, ClusterRoleBinding, Deployment, and Service."
                )
            )
        } else {
            checks.append(
                OpenCostPreflightCheck(
                    id: "rbac-permissions",
                    title: "Cluster & namespace RBAC permissions",
                    status: .failed,
                    detail: "Missing required permissions: \(missingPermissions.joined(separator: ", ")).",
                    remediation: "Switch to a context with cluster-admin or grant permissions for `\(Self.targetNamespace)` plus ClusterRole/ClusterRoleBinding creation."
                )
            )
        }

        // 3. Discover Services (Prometheus & existing OpenCost/Kubecost)
        var discoveredPrometheus: DiscoveredPrometheusEndpoint?
        var existingProviderEndpoint: String?
        if rbacConnectionError == nil {
            if let servicesJSON = try? await runKubectlStdout(
                context: context,
                arguments: ["get", "services", "--all-namespaces", "--output=json"],
                timeout: 20
            ) {
                existingProviderEndpoint = Self.detectExistingCostService(fromServicesJSON: servicesJSON)
                if var candidate = Self.discoverPrometheusService(fromServicesJSON: servicesJSON) {
                    if let endpointsJSON = try? await runKubectlStdout(
                        context: context,
                        arguments: ["get", "pods", "-n", candidate.namespace, "--output=json"],
                        timeout: 12
                    ) {
                        candidate.hasReadyEndpoints = Self.hasRunningPrometheusPod(fromPodsJSON: endpointsJSON)
                    }
                    discoveredPrometheus = candidate
                }
            }
        }

        if let existingProviderEndpoint {
            checks.append(
                OpenCostPreflightCheck(
                    id: "existing-provider",
                    title: "Existing cost service discovery",
                    status: .warning,
                    detail: "Detected existing cost service at \(existingProviderEndpoint). Proceeding will run `helm upgrade --install` for \(Self.releaseName) in `\(Self.targetNamespace)`."
                )
            )
        }

        let readyPrometheus = discoveredPrometheus?.hasReadyEndpoints == true ? discoveredPrometheus : nil
        if let prom = discoveredPrometheus {
            if prom.hasReadyEndpoints {
                checks.append(
                    OpenCostPreflightCheck(
                        id: "prometheus-discovery",
                        title: "In-cluster Prometheus discovery",
                        status: .passed,
                        detail: "Discovered active Prometheus service `\(prom.namespace)/\(prom.serviceName)` on port \(prom.port) (\(prom.inClusterURL))."
                    )
                )
            } else {
                checks.append(
                    OpenCostPreflightCheck(
                        id: "prometheus-discovery",
                        title: "In-cluster Prometheus discovery",
                        status: .warning,
                        detail: "Found Prometheus service `\(prom.namespace)/\(prom.serviceName):\(prom.port)`, but no Ready Prometheus pods were detected in `\(prom.namespace)`.",
                        remediation: "CTX will use OpenCost Collector storage instead. Restore Prometheus first if the existing time-series backend should be retained."
                    )
                )
            }
        } else {
            checks.append(
                OpenCostPreflightCheck(
                    id: "prometheus-discovery",
                    title: "In-cluster Prometheus discovery",
                    status: .warning,
                    detail: "No in-cluster Prometheus server Service was detected across any namespace.",
                    remediation: "CTX will use OpenCost's low-footprint Collector data source with a 1 GiB persistent volume."
                )
            )
        }

        // 4. Discover StorageClasses & verify PVC safety
        var storageInfo = DiscoveredStorageClassInfo(
            classes: [],
            defaultClasses: [],
            summary: "OpenCost will run statelessly against Prometheus (`persistence.enabled=false`), so no PersistentVolumeClaim is created."
        )
        if rbacConnectionError == nil,
           let scJSON = try? await runKubectlStdout(
               context: context,
               arguments: ["get", "storageclasses", "--output=json"],
               timeout: 12
           ) {
            storageInfo = Self.parseStorageClasses(fromJSON: scJSON)
        }
        let collectorStorageClass = readyPrometheus == nil && storageInfo.defaultClasses.count == 1
            ? storageInfo.defaultClasses[0]
            : nil
        let storageStatus: OpenCostCheckStatus = readyPrometheus != nil || collectorStorageClass != nil ? .passed : .failed
        let storageDetail: String
        let storageRemediation: String?
        if readyPrometheus != nil {
            storageDetail = storageInfo.summary
            storageRemediation = nil
        } else if let collectorStorageClass {
            storageDetail = "OpenCost Collector will persist its local metrics in a 1 GiB PVC using `\(collectorStorageClass)`."
            storageRemediation = nil
        } else {
            storageDetail = "Collector mode requires exactly one default StorageClass; detected \(storageInfo.defaultClasses.count)."
            storageRemediation = "Configure one default StorageClass, or restore a Ready Prometheus service, then re-run preflight."
        }
        checks.append(
            OpenCostPreflightCheck(
                id: "storageclass-check",
                title: "StorageClass & PVC assessment",
                status: storageStatus,
                detail: storageDetail,
                remediation: storageRemediation
            )
        )

        let isHelm4 = (helmVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("v4.")
        var plannedResources = Self.buildPlannedResources(
            namespace: Self.targetNamespace,
            releaseName: Self.releaseName,
            prometheus: readyPrometheus,
            collectorStorageClass: collectorStorageClass
        )
        var chartVersion: String?
        var appVersion: String?
        var containerImage: String?
        var renderedManifestYAML: String?
        var serverDryRunVerified = false

        // 5. Real Server-Side Admission Dry-Run (`helm upgrade --install ... --dry-run=server`)
        let canAttemptDryRun = checks.allSatisfy { $0.status != .failed }
        if canAttemptDryRun, let helmPath {
            _ = try? await runHelm(
                helmPath: helmPath,
                context: context,
                arguments: ["repo", "add", Self.chartRepositoryName, Self.chartRepositoryURL, "--force-update"],
                includeContextFlags: false,
                timeout: 20
            )
            let dryRunArgs = Self.helmUpgradeInstallArguments(
                clusterName: clusterName,
                prometheus: readyPrometheus,
                collectorStorageClass: collectorStorageClass,
                isHelm4: isHelm4,
                dryRunServer: true
            )
            if let dryRunResult = try? await runHelm(
                helmPath: helmPath,
                context: context,
                arguments: dryRunArgs,
                includeContextFlags: true,
                timeout: 30
            ) {
                if dryRunResult.exitCode == 0 {
                    serverDryRunVerified = true
                    let parsed = Self.parseDryRunOutput(
                        dryRunResult.stdout,
                        namespace: Self.targetNamespace,
                        releaseName: Self.releaseName,
                        prometheus: readyPrometheus,
                        collectorStorageClass: collectorStorageClass
                    )
                    chartVersion = parsed.chartVersion
                    appVersion = parsed.appVersion
                    containerImage = parsed.containerImage
                    renderedManifestYAML = parsed.manifestYAML
                    if !parsed.resources.isEmpty {
                        plannedResources = parsed.resources
                    }
                    let versionBadge = [chartVersion, appVersion.map { "app v\($0)" }]
                        .compactMap { $0 }
                        .joined(separator: ", ")
                    let versionSuffix = versionBadge.isEmpty ? "" : " (\(versionBadge))"
                    checks.append(
                        OpenCostPreflightCheck(
                            id: "server-dry-run",
                            title: "Kubernetes API server dry-run",
                            status: .passed,
                            detail: "API server validated \(plannedResources.count) resources\(versionSuffix) via `--dry-run=server`."
                        )
                    )
                } else {
                    let err = Self.cleanError(dryRunResult)
                    checks.append(
                        OpenCostPreflightCheck(
                            id: "server-dry-run",
                            title: "Kubernetes API server dry-run",
                            status: .failed,
                            detail: "Server-side dry-run rejected the release: \(err)",
                            remediation: "Inspect admission webhook or RBAC policies for namespace `\(Self.targetNamespace)`: \(err)"
                        )
                    )
                }
            }
        }

        let commandPreview: [[String]]
        if readyPrometheus != nil || collectorStorageClass != nil {
            commandPreview = Self.buildCommandPreview(
                context: context,
                clusterName: clusterName,
                prometheus: readyPrometheus,
                collectorStorageClass: collectorStorageClass,
                isHelm4: isHelm4
            )
        } else {
            commandPreview = []
        }

        let failedChecks = checks.filter { $0.status == .failed }
        let canProceed = failedChecks.isEmpty && (readyPrometheus != nil || collectorStorageClass != nil) && helmPath != nil
        let remediationSummary: String? = failedChecks.isEmpty
            ? nil
            : failedChecks.compactMap(\.remediation).joined(separator: "\n\n")

        return OpenCostSetupPreflightReport(
            contextName: context.contextName,
            clusterName: clusterName,
            isProduction: isProduction,
            targetNamespace: Self.targetNamespace,
            releaseName: Self.releaseName,
            chartRepositoryURL: Self.chartRepositoryURL,
            chartReference: Self.chartReference,
            helmExecutablePath: helmPath,
            helmVersion: helmVersion,
            chartVersion: chartVersion,
            appVersion: appVersion,
            containerImage: containerImage,
            serverDryRunVerified: serverDryRunVerified,
            renderedManifestYAML: renderedManifestYAML,
            existingProviderEndpoint: existingProviderEndpoint,
            discoveredPrometheus: discoveredPrometheus,
            storageClassInfo: storageInfo,
            checks: checks,
            plannedResources: plannedResources,
            commandArgumentsPreview: commandPreview,
            canProceedToInstall: canProceed,
            remediationSummary: remediationSummary
        )
    }

    public func installAndVerify(
        context: KubernetesContextProfile,
        preflight: OpenCostSetupPreflightReport,
        window: FinOpsTimeWindow,
        aggregation: FinOpsAggregation,
        onStep: @Sendable (OpenCostSetupStepLog) -> Void
    ) async -> OpenCostSetupExecutionResult {
        var steps: [OpenCostSetupStepLog] = []
        func record(_ step: String, _ status: OpenCostCheckStatus, _ detail: String) {
            let entry = OpenCostSetupStepLog(step: step, status: status, detail: detail)
            steps.append(entry)
            onStep(entry)
        }

        guard preflight.canProceedToInstall,
              let helmPath = preflight.helmExecutablePath ?? helmPathResolver()
        else {
            let msg = "Installation blocked because preflight safety conditions are not satisfied."
            record("Preflight gate", .failed, msg)
            return OpenCostSetupExecutionResult(
                success: false,
                summary: msg,
                steps: steps,
                remediation: preflight.remediationSummary
            )
        }

        let isHelm4 = (preflight.helmVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("v4.")
        let prometheus = preflight.discoveredPrometheus?.hasReadyEndpoints == true ? preflight.discoveredPrometheus : nil
        let collectorStorageClass = prometheus == nil && preflight.storageClassInfo.defaultClasses.count == 1
            ? preflight.storageClassInfo.defaultClasses[0]
            : nil
        let installArgs = Self.helmUpgradeInstallArguments(
            clusterName: preflight.clusterName,
            prometheus: prometheus,
            collectorStorageClass: collectorStorageClass,
            isHelm4: isHelm4,
            dryRunServer: false
        )
        let dryRunArgs = Self.helmUpgradeInstallArguments(
            clusterName: preflight.clusterName,
            prometheus: prometheus,
            collectorStorageClass: collectorStorageClass,
            isHelm4: isHelm4,
            dryRunServer: true
        )

        do {
            // Step 1: Register official OpenCost Helm chart repository
            record(
                "Configure OpenCost Helm repository",
                .passed,
                "Registering \(Self.chartRepositoryName) (\(Self.chartRepositoryURL)) without shell interpolation."
            )
            let repoAddResult = try await runHelm(
                helmPath: helmPath,
                context: context,
                arguments: ["repo", "add", Self.chartRepositoryName, Self.chartRepositoryURL, "--force-update"],
                includeContextFlags: false,
                timeout: 25
            )
            guard repoAddResult.exitCode == 0 else {
                let err = Self.cleanError(repoAddResult)
                record("Configure OpenCost Helm repository", .failed, err)
                return OpenCostSetupExecutionResult(
                    success: false,
                    summary: "Failed to add OpenCost Helm repository: \(err)",
                    steps: steps,
                    remediation: "Check network connectivity to \(Self.chartRepositoryURL) and run `helm repo add \(Self.chartRepositoryName) \(Self.chartRepositoryURL)`."
                )
            }

            let repoUpdateResult = try await runHelm(
                helmPath: helmPath,
                context: context,
                arguments: ["repo", "update", Self.chartRepositoryName],
                includeContextFlags: false,
                timeout: 30
            )
            guard repoUpdateResult.exitCode == 0 else {
                let err = Self.cleanError(repoUpdateResult)
                record("Update OpenCost chart index", .failed, err)
                return OpenCostSetupExecutionResult(
                    success: false,
                    summary: "Failed to update OpenCost Helm chart index: \(err)",
                    steps: steps
                )
            }
            record("Update OpenCost chart index", .passed, "Synchronized latest `\(Self.chartReference)` chart metadata.")

            // Step 2: Server-side dry-run against Kubernetes API
            let dryRunResult = try await runHelm(
                helmPath: helmPath,
                context: context,
                arguments: dryRunArgs,
                includeContextFlags: true,
                timeout: 45
            )
            guard dryRunResult.exitCode == 0 else {
                let err = Self.cleanError(dryRunResult)
                record("Server-side admission dry-run", .failed, err)
                return OpenCostSetupExecutionResult(
                    success: false,
                    summary: "Kubernetes API server dry-run rejected OpenCost manifest: \(err)",
                    steps: steps,
                    remediation: "No cluster changes were applied. Inspect admission/RBAC error above before retrying."
                )
            }
            record(
                "Server-side admission dry-run",
                .passed,
                "Kubernetes API server validated all OpenCost manifests (`--dry-run=server`)."
            )

            // Step 3: Execute Helm install/upgrade
            let installResult = try await runHelm(
                helmPath: helmPath,
                context: context,
                arguments: installArgs,
                includeContextFlags: true,
                timeout: 130
            )
            guard installResult.exitCode == 0 else {
                let err = Self.cleanError(installResult)
                record("Install OpenCost release", .failed, err)
                return OpenCostSetupExecutionResult(
                    success: false,
                    summary: "Helm install of OpenCost failed: \(err)",
                    steps: steps,
                    remediation: "Check pod events in namespace `\(Self.targetNamespace)`: `kubectl get events -n \(Self.targetNamespace) --sort-by=.lastTimestamp`."
                )
            }
            record(
                "Install OpenCost release",
                .passed,
                prometheus.map { "Deployed release `\(Self.releaseName)` in namespace `\(Self.targetNamespace)` wired to `\($0.inClusterURL)`." }
                    ?? "Deployed release `\(Self.releaseName)` in namespace `\(Self.targetNamespace)` using the persistent OpenCost Collector data source."
            )

            // Step 4: Verify Deployment rollout readiness
            let rolloutResult = try await runKubectlResult(
                context: context,
                arguments: [
                    "rollout", "status",
                    "deployment/\(Self.releaseName)",
                    "-n", Self.targetNamespace,
                    "--timeout=90s"
                ],
                timeout: 95
            )
            guard rolloutResult.exitCode == 0 else {
                let err = Self.cleanError(rolloutResult)
                record("Verify Deployment readiness", .failed, err)
                return OpenCostSetupExecutionResult(
                    success: false,
                    summary: "OpenCost Deployment did not become Ready within 90s: \(err)",
                    steps: steps,
                    remediation: "Inspect pod logs with `kubectl logs -n \(Self.targetNamespace) deployment/\(Self.releaseName)`."
                )
            }
            record(
                "Verify Deployment readiness",
                .passed,
                "Deployment `\(Self.targetNamespace)/\(Self.releaseName)` is Running and Ready."
            )

            // Step 5: Verify OpenCost `/allocation` API responds with real cost allocations
            let now = Date()
            let start = now.addingTimeInterval(-max(1, window.daysFactor) * 86_400)
            var lastCostResult = KubernetesCostReadResult(message: "Waiting for OpenCost allocation endpoint...")
            for attempt in 1...4 {
                lastCostResult = await costReader.report(
                    context: context,
                    window: window,
                    customStart: start,
                    customEnd: now,
                    aggregation: aggregation
                )
                if let verifiedReport = lastCostResult.report {
                    record(
                        "Verify OpenCost allocation API",
                        .passed,
                        "Verified `/allocation` API response (\(verifiedReport.rows.count) allocation groups, window spend $\(String(format: "%.2f", verifiedReport.summary.windowSpendUSD)))."
                    )
                    return OpenCostSetupExecutionResult(
                        success: true,
                        summary: prometheus.map {
                            "OpenCost is installed, healthy, and returning live cost allocations using `\($0.namespace)/\($0.serviceName)`."
                        } ?? "OpenCost is installed, healthy, and returning live cost allocations from its Collector data source.",
                        steps: steps,
                        verifiedReport: verifiedReport
                    )
                }
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }

            let warnDetail = lastCostResult.message.isEmpty
                ? "OpenCost Service is running, but `/allocation` has not finished its initial Prometheus scrape yet."
                : lastCostResult.message
            record("Verify OpenCost allocation API", .failed, warnDetail)
            return OpenCostSetupExecutionResult(
                success: false,
                summary: "OpenCost was deployed and is Ready, but setup is not complete because the allocation API could not be verified: \(warnDetail)",
                steps: steps,
                verifiedReport: nil,
                remediation: "Do not reinstall the release. Retry the connection first; if it still fails, inspect `kubectl logs -n \(Self.targetNamespace) deployment/\(Self.releaseName)` and verify the Service has ready endpoints."
            )
        } catch {
            let err = error.localizedDescription
            record("OpenCost installation error", .failed, err)
            return OpenCostSetupExecutionResult(
                success: false,
                summary: "OpenCost setup failed: \(err)",
                steps: steps
            )
        }
    }

    // MARK: - Discovery & Parsing Helpers (Exposed for unit testing)

    public static func discoverPrometheusService(fromServicesJSON text: String) -> DiscoveredPrometheusEndpoint? {
        guard
            let data = text.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["items"] as? [[String: Any]]
        else { return nil }

        let excludedSubstrings = [
            "alertmanager",
            "operator",
            "node-exporter",
            "kube-state-metrics",
            "grafana",
            "coredns",
            "kube-proxy",
            "kube-scheduler",
            "kube-controller-manager",
            "kube-etcd",
            "kubelet",
            "pushgateway",
            "cloudwatch-exporter",
            "opencost",
            "kubecost",
            "webhook"
        ]

        struct Candidate {
            let endpoint: DiscoveredPrometheusEndpoint
            let rank: Int
        }

        var candidates: [Candidate] = []
        for item in items {
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            let labels = metadata["labels"] as? [String: Any] ?? [:]
            let name = metadata["name"] as? String ?? ""
            let namespace = metadata["namespace"] as? String ?? ""
            guard !name.isEmpty, !namespace.isEmpty else { continue }

            let lowerName = name.lowercased()
            if excludedSubstrings.contains(where: { lowerName.contains($0) }) {
                continue
            }

            let appName = (labels["app.kubernetes.io/name"] as? String ?? labels["app"] as? String ?? "").lowercased()
            let component = (labels["app.kubernetes.io/component"] as? String ?? labels["component"] as? String ?? "").lowercased()
            if excludedSubstrings.contains(where: { appName.contains($0) || component.contains($0) }) {
                continue
            }

            let isPrometheusIdentity = lowerName.contains("prometheus")
                || appName == "prometheus"
                || (appName.contains("prometheus") && (component.isEmpty || component == "server" || component == "prometheus"))
            guard isPrometheusIdentity else { continue }

            let spec = item["spec"] as? [String: Any] ?? [:]
            let clusterIP = (spec["clusterIP"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isHeadless = clusterIP.lowercased() == "none"

            let ports = spec["ports"] as? [[String: Any]] ?? []
            let preferredPortEntry = ports.first { portInt($0["port"]) == 9090 }
                ?? ports.first { portInt($0["port"]) == 80 }
                ?? ports.first { ($0["name"] as? String ?? "").lowercased().contains("http") || ($0["name"] as? String ?? "").lowercased().contains("web") }
                ?? ports.first
            guard let port = preferredPortEntry.flatMap({ portInt($0["port"]) }) else { continue }

            var rank = 50
            if !isHeadless { rank -= 25 }
            if lowerName.hasSuffix("-prometheus") || lowerName == "prometheus-server" || lowerName == "prometheus-k8s" || lowerName == "prometheus" {
                rank -= 15
            }
            if port == 9090 { rank -= 5 }
            if namespace == "monitoring" || namespace == "prometheus" || namespace == "observability" {
                rank -= 5
            }

            candidates.append(
                Candidate(
                    endpoint: DiscoveredPrometheusEndpoint(
                        namespace: namespace,
                        serviceName: name,
                        port: port,
                        hasReadyEndpoints: true
                    ),
                    rank: rank
                )
            )
        }

        return candidates.sorted { lhs, rhs in
            lhs.rank == rhs.rank ? lhs.endpoint.serviceName < rhs.endpoint.serviceName : lhs.rank < rhs.rank
        }.first?.endpoint
    }

    public static func detectExistingCostService(fromServicesJSON text: String) -> String? {
        guard
            let data = text.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["items"] as? [[String: Any]]
        else { return nil }

        for item in items {
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            let labels = metadata["labels"] as? [String: Any] ?? [:]
            let name = metadata["name"] as? String ?? ""
            let namespace = metadata["namespace"] as? String ?? ""
            let identity = ([name] + ["app.kubernetes.io/name", "app", "app.kubernetes.io/instance"].compactMap { labels[$0] as? String })
                .joined(separator: " ")
                .lowercased()
            guard identity.contains("opencost") || identity.contains("kubecost") || identity.contains("cost-analyzer") else {
                continue
            }
            let spec = item["spec"] as? [String: Any] ?? [:]
            let ports = spec["ports"] as? [[String: Any]] ?? []
            if let port = ports.compactMap({ portInt($0["port"]) }).first(where: { $0 == 9003 || $0 == 9090 }) {
                return "\(namespace)/\(name):\(port)"
            }
        }
        return nil
    }

    public static func hasRunningPrometheusPod(fromPodsJSON text: String) -> Bool {
        guard
            let data = text.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["items"] as? [[String: Any]]
        else { return false }

        for item in items {
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            let name = (metadata["name"] as? String ?? "").lowercased()
            guard name.contains("prometheus"),
                  !name.contains("node-exporter"),
                  !name.contains("kube-state-metrics"),
                  !name.contains("alertmanager")
            else { continue }
            let status = item["status"] as? [String: Any] ?? [:]
            let phase = (status["phase"] as? String ?? "").lowercased()
            if phase == "running" {
                return true
            }
        }
        return false
    }

    public static func parseStorageClasses(fromJSON text: String) -> DiscoveredStorageClassInfo {
        guard
            let data = text.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["items"] as? [[String: Any]]
        else {
            return DiscoveredStorageClassInfo(
                classes: [],
                defaultClasses: [],
                summary: "OpenCost is configured with `persistence.enabled=false` (queries Prometheus directly without creating a PVC)."
            )
        }

        var classes: [String] = []
        var defaults: [String] = []
        for item in items {
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            let name = metadata["name"] as? String ?? ""
            guard !name.isEmpty else { continue }
            classes.append(name)
            let annotations = metadata["annotations"] as? [String: Any] ?? [:]
            let isDefault = (annotations["storageclass.kubernetes.io/is-default-class"] as? String ?? "").lowercased() == "true"
                || (annotations["storageclass.beta.kubernetes.io/is-default-class"] as? String ?? "").lowercased() == "true"
            if isDefault {
                defaults.append(name)
            }
        }

        let summary: String
        if defaults.count > 1 {
            summary = "Cluster has \(classes.count) StorageClasses with multiple defaults (\(defaults.joined(separator: ", "))). OpenCost will install with `persistence.enabled=false` (backed by Prometheus) to avoid PVC default StorageClass conflicts."
        } else if let singleDefault = defaults.first {
            summary = "Cluster default StorageClass is `\(singleDefault)` (\(classes.count) total). OpenCost will install with `persistence.enabled=false` (stateless Prometheus backend, no PVC created)."
        } else {
            summary = "No default StorageClass detected (\(classes.count) total). OpenCost will install with `persistence.enabled=false` (stateless Prometheus backend, no PVC required)."
        }

        return DiscoveredStorageClassInfo(classes: classes, defaultClasses: defaults, summary: summary)
    }

    public static func buildPlannedResources(
        namespace: String,
        releaseName: String,
        prometheus: DiscoveredPrometheusEndpoint?,
        collectorStorageClass: String? = nil
    ) -> [OpenCostPlannedResource] {
        let backendSummary = prometheus.map {
            "stateless `persistence.enabled=false` querying \($0.inClusterURL)"
        } ?? "Collector data source with persistent local metrics"
        var resources = [
            OpenCostPlannedResource(
                kind: "Namespace",
                name: namespace,
                namespace: nil,
                summary: "Dedicated namespace for the OpenCost release (`--create-namespace`)."
            ),
            OpenCostPlannedResource(
                kind: "ServiceAccount",
                name: releaseName,
                namespace: namespace,
                summary: "Pod identity for the OpenCost cost-model exporter."
            ),
            OpenCostPlannedResource(
                kind: "ClusterRole",
                name: releaseName,
                namespace: nil,
                summary: "Read-only RBAC access to nodes, pods, namespaces, PVs, PVCs, StorageClasses, Services, and workload controllers."
            ),
            OpenCostPlannedResource(
                kind: "ClusterRoleBinding",
                name: releaseName,
                namespace: nil,
                summary: "Binds ClusterRole/\(releaseName) to ServiceAccount/\(namespace)/\(releaseName)."
            ),
            OpenCostPlannedResource(
                kind: "Deployment",
                name: releaseName,
                namespace: namespace,
                summary: "1-replica OpenCost exporter (`ghcr.io/opencost/opencost`, port 9003, \(backendSummary))."
            ),
            OpenCostPlannedResource(
                kind: "Service",
                name: releaseName,
                namespace: namespace,
                summary: "ClusterIP service on port 9003 (`/allocation` API consumed by CTX FinOps)."
            )
        ]
        if let collectorStorageClass {
            resources.append(
                OpenCostPlannedResource(
                    kind: "PersistentVolumeClaim",
                    name: releaseName,
                    namespace: namespace,
                    summary: "1 GiB ReadWriteOnce storage for OpenCost Collector using `\(collectorStorageClass)`."
                )
            )
        }
        return resources
    }

    public static func helmUpgradeInstallArguments(
        clusterName: String,
        prometheus: DiscoveredPrometheusEndpoint?,
        collectorStorageClass: String? = nil,
        isHelm4: Bool,
        dryRunServer: Bool
    ) -> [String] {
        var args: [String] = [
            "upgrade", "--install",
            releaseName,
            chartReference,
            "--namespace", targetNamespace,
            "--create-namespace"
        ]
        if dryRunServer {
            args.append("--dry-run=server")
        } else {
            args.append(isHelm4 ? "--rollback-on-failure" : "--atomic")
            args.append(contentsOf: ["--timeout", "2m0s"])
        }
        if let prometheus {
            args.append(contentsOf: [
                "--set", "opencost.prometheus.internal.enabled=true",
                "--set-string", "opencost.prometheus.internal.serviceName=\(prometheus.serviceName)",
                "--set-string", "opencost.prometheus.internal.namespaceName=\(prometheus.namespace)",
                "--set", "opencost.prometheus.internal.port=\(prometheus.port)",
                "--set", "opencost.exporter.collectorDataSource.enabled=false",
                "--set", "opencost.exporter.persistence.enabled=false"
            ])
        } else if let collectorStorageClass {
            args.append(contentsOf: [
                "--set", "opencost.prometheus.internal.enabled=false",
                "--set", "opencost.exporter.collectorDataSource.enabled=true",
                "--set", "opencost.exporter.collectorDataSource.retention1d=30",
                "--set", "opencost.exporter.persistence.enabled=true",
                "--set-string", "opencost.exporter.persistence.storageClass=\(collectorStorageClass)",
                "--set", "opencost.exporter.persistence.accessMode=ReadWriteOnce",
                "--set", "opencost.exporter.persistence.size=1Gi",
                "--set-string", "opencost.exporter.persistence.mountPath=/var/configs"
            ])
        }
        args.append(contentsOf: [
            "--set-string", "opencost.exporter.defaultClusterId=\(clusterName)",
            "--set", "opencost.exporter.resources.requests.cpu=10m",
            "--set", "opencost.exporter.resources.requests.memory=55Mi",
            "--set", "opencost.ui.enabled=false",
            "--set", "opencost.mcp.enabled=false"
        ])
        return args
    }

    public static func buildCommandPreview(
        context: KubernetesContextProfile,
        clusterName: String,
        prometheus: DiscoveredPrometheusEndpoint?,
        collectorStorageClass: String? = nil,
        isHelm4: Bool
    ) -> [[String]] {
        var contextFlags = ["--kube-context", context.contextName]
        let kubeconfig = context.kubeconfigPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kubeconfig.isEmpty {
            contextFlags.append(contentsOf: ["--kubeconfig", kubeconfig])
        }
        let dryRun = ["helm"] + helmUpgradeInstallArguments(
            clusterName: clusterName,
            prometheus: prometheus,
            collectorStorageClass: collectorStorageClass,
            isHelm4: isHelm4,
            dryRunServer: true
        ) + contextFlags
        let install = ["helm"] + helmUpgradeInstallArguments(
            clusterName: clusterName,
            prometheus: prometheus,
            collectorStorageClass: collectorStorageClass,
            isHelm4: isHelm4,
            dryRunServer: false
        ) + contextFlags
        return [
            ["helm", "repo", "add", chartRepositoryName, chartRepositoryURL, "--force-update"],
            ["helm", "repo", "update", chartRepositoryName],
            dryRun,
            install
        ]
    }

    public static func sanitizedClusterIdentifier(from raw: String) -> String {
        let base = raw.split(separator: "/").last.map(String.init) ?? raw
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return cleaned.isEmpty ? "default-cluster" : cleaned
    }

    public struct ParsedDryRunManifest: Equatable, Sendable {
        public var chartVersion: String?
        public var appVersion: String?
        public var containerImage: String?
        public var manifestYAML: String?
        public var resources: [OpenCostPlannedResource]
    }

    public static func parseDryRunOutput(
        _ stdout: String,
        namespace: String,
        releaseName: String,
        prometheus: DiscoveredPrometheusEndpoint?,
        collectorStorageClass: String? = nil
    ) -> ParsedDryRunManifest {
        guard let manifestRange = stdout.range(of: "MANIFEST:\n") else {
            return ParsedDryRunManifest(
                chartVersion: nil,
                appVersion: nil,
                containerImage: nil,
                manifestYAML: nil,
                resources: buildPlannedResources(
                    namespace: namespace,
                    releaseName: releaseName,
                    prometheus: prometheus,
                    collectorStorageClass: collectorStorageClass
                )
            )
        }
        let manifest = String(stdout[manifestRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manifest.isEmpty else {
            return ParsedDryRunManifest(
                chartVersion: nil,
                appVersion: nil,
                containerImage: nil,
                manifestYAML: nil,
                resources: buildPlannedResources(
                    namespace: namespace,
                    releaseName: releaseName,
                    prometheus: prometheus,
                    collectorStorageClass: collectorStorageClass
                )
            )
        }

        var chartVersion: String?
        var appVersion: String?
        var containerImage: String?
        var resources: [OpenCostPlannedResource] = [
            OpenCostPlannedResource(
                kind: "Namespace",
                name: namespace,
                namespace: nil,
                summary: "Created via `--create-namespace` if not already present."
            )
        ]

        let documents = manifest.components(separatedBy: "\n---")
        for doc in documents {
            var kind: String?
            var name: String?
            var docNamespace: String?
            var sourceTemplate: String?
            var inMetadata = false

            for rawLine in doc.components(separatedBy: .newlines) {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# Source:") {
                    sourceTemplate = trimmed.replacingOccurrences(of: "# Source:", with: "").trimmingCharacters(in: .whitespaces)
                } else if rawLine.hasPrefix("kind:") {
                    kind = rawLine.replacingOccurrences(of: "kind:", with: "").trimmingCharacters(in: .whitespaces)
                } else if rawLine.hasPrefix("metadata:") {
                    inMetadata = true
                } else if !rawLine.hasPrefix(" ") && !rawLine.hasPrefix("\t") && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    inMetadata = false
                } else if inMetadata {
                    if rawLine.hasPrefix("  name:"), name == nil {
                        name = rawLine.replacingOccurrences(of: "  name:", with: "").trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    } else if rawLine.hasPrefix("  namespace:"), docNamespace == nil {
                        docNamespace = rawLine.replacingOccurrences(of: "  namespace:", with: "").trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    }
                }

                if chartVersion == nil, trimmed.hasPrefix("helm.sh/chart:") {
                    chartVersion = trimmed.replacingOccurrences(of: "helm.sh/chart:", with: "").trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
                if appVersion == nil, trimmed.hasPrefix("app.kubernetes.io/version:") {
                    appVersion = trimmed.replacingOccurrences(of: "app.kubernetes.io/version:", with: "").trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
                if containerImage == nil, (trimmed.hasPrefix("image:") || trimmed.hasPrefix("- image:")) {
                    let rawImage = trimmed
                        .replacingOccurrences(of: "- image:", with: "")
                        .replacingOccurrences(of: "image:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    containerImage = rawImage.components(separatedBy: "@").first ?? rawImage
                }
            }

            if let kind, let name {
                let summary: String
                switch kind {
                case "Deployment":
                    let img = containerImage ?? "ghcr.io/opencost/opencost"
                    summary = prometheus.map { "\(img) → \($0.inClusterURL)" }
                        ?? "\(img) → OpenCost Collector"
                case "Service":
                    summary = "ClusterIP :9003 (`/allocation` API)"
                case "ClusterRole":
                    summary = "Read-only cluster RBAC (\(sourceTemplate ?? "clusterrole.yaml"))"
                case "ClusterRoleBinding":
                    summary = "Binds ClusterRole/\(name) → ServiceAccount/\(namespace)/\(releaseName)"
                default:
                    summary = sourceTemplate ?? "Validated via Helm server dry-run"
                }
                resources.append(
                    OpenCostPlannedResource(
                        kind: kind,
                        name: name,
                        namespace: docNamespace,
                        summary: summary
                    )
                )
            }
        }

        return ParsedDryRunManifest(
            chartVersion: chartVersion,
            appVersion: appVersion,
            containerImage: containerImage,
            manifestYAML: manifest,
            resources: resources
        )
    }

    // MARK: - Private Execution Helpers

    private func runKubectlResult(
        context: KubernetesContextProfile,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> KubectlResult {
        var command = try runner.inspectionCommand(
            context: context.contextName,
            arguments: context.kubeconfigArguments + arguments
        )
        command.environmentOverrides = context.kubeconfigEnvironment
        return try await runner.run(command, timeout: timeout)
    }

    private func runKubectlStdout(
        context: KubernetesContextProfile,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> String {
        let result = try await runKubectlResult(context: context, arguments: arguments, timeout: timeout)
        guard result.exitCode == 0 else {
            throw NSError(
                domain: "KubernetesOpenCostSetupService",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: Self.cleanError(result)]
            )
        }
        return result.stdout
    }

    private func runHelm(
        helmPath: String,
        context: KubernetesContextProfile,
        arguments: [String],
        includeContextFlags: Bool,
        timeout: TimeInterval
    ) async throws -> KubectlResult {
        let kubeconfig = context.kubeconfigPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var fullArguments = arguments
        if includeContextFlags {
            fullArguments.append(contentsOf: ["--kube-context", context.contextName])
            if !kubeconfig.isEmpty {
                fullArguments.append(contentsOf: ["--kubeconfig", kubeconfig])
            }
        }
        let command = KubectlCommand(
            executablePath: helmPath,
            arguments: fullArguments,
            environmentOverrides: kubeconfig.isEmpty ? [:] : ["KUBECONFIG": kubeconfig]
        )
        return try await runner.run(command, timeout: timeout)
    }

    private static func portInt(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    private static func cleanError(_ result: KubectlResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? "Command exited with code \(result.exitCode)." : stdout
    }
}
