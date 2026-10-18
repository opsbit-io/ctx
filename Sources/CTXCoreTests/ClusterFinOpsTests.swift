import CTXCore
import Foundation

public func runClusterFinOpsTests() {
    assert(!CloudPricingProfile.aws.hasExplicitRates)
    assert(!CloudPricingProfile.gcp.hasExplicitRates)
    assert(!CloudPricingProfile.azure.hasExplicitRates)

    let fixturePricing = CloudPricingProfile(
        providerName: "Test fixture",
        cpuHourlyPerCore: 0.03,
        memoryHourlyPerGiB: 0.004,
        storageMonthlyPerGB: 0.08,
        loadBalancerMonthly: 0
    )
    let engine = ClusterFinOpsEngine(pricing: fixturePricing)

    let emptyReport = engine.analyze(
        pods: [],
        nodes: [],
        pvcs: [],
        workloads: []
    )
    assert(emptyReport.summary.windowSpendUSD == 0, "Missing cluster capacity must not be replaced with an invented baseline")
    assert(emptyReport.summary.monthlyRunRateUSD == 0, "Missing inputs must not create a monthly estimate")
    assert(emptyReport.timeSeries.isEmpty, "Missing history must remain missing")

    let pods = [
        KubernetesResourceRow(
            id: "api-service-758bd7c96-x418a",
            cells: [
                "Namespace": "production",
                "Node": "node-1",
                "CPU": "1000m",
                "Memory": "2Gi",
                "Owner": "api-service"
            ]
        ),
        KubernetesResourceRow(
            id: "web-frontend-918ff89c-a812k",
            cells: [
                "Namespace": "frontend",
                "Node": "node-1",
                "CPU": "250m",
                "Memory": "512Mi",
                "Owner": "web-frontend"
            ]
        )
    ]

    let nodes = [
        KubernetesResourceRow(
            id: "node-1",
            cells: [
                "CPU": "4000m",
                "Memory": "16Gi"
            ]
        )
    ]

    let pvcs = [
        KubernetesResourceRow(
            id: "data-claim",
            cells: [
                "Namespace": "production",
                "Capacity": "50Gi",
                "Status": "Bound"
            ]
        )
    ]

    let report = engine.analyze(
        pods: pods,
        nodes: nodes,
        pvcs: pvcs,
        workloads: [],
        window: .d7,
        aggregation: .namespace
    )

    assert(report.window == .d7, "Window should match")
    assert(report.aggregation == .namespace, "Aggregation should match")
    assert(!report.rows.isEmpty, "Report rows should not be empty")
    assert(report.summary.windowSpendUSD > 0, "Window spend should be positive")
    assert(report.summary.monthlyRunRateUSD > 0, "Monthly run rate should be positive")

    let productionRow = report.rows.first { $0.name == "production" }
    assert(productionRow != nil, "Production namespace row should exist")
    assert((productionRow?.breakdown.cpuCost ?? 0) > 0, "CPU cost should be positive")
    assert((productionRow?.breakdown.storageCost ?? 0) > 0, "Storage cost should be positive")
    assert(report.timeSeries.isEmpty, "A current snapshot must not be presented as historical data")

    // Workload aggregation test
    let workloadReport = engine.analyze(
        pods: pods,
        nodes: nodes,
        pvcs: pvcs,
        workloads: [],
        window: .d30,
        aggregation: .workload
    )
    assert(workloadReport.rows.count == 2, "Should aggregate into 2 distinct workloads")
    let wlRow = workloadReport.rows.first { $0.name == "api-service" }
    assert(wlRow != nil, "Workload row should exist")
    assert(wlRow?.namespace == "production")

    // A Pending PVC is not proof of a billable volume or a safe deletion target.
    let orphanPvc = [
        KubernetesResourceRow(
            id: "orphan-disk",
            cells: [
                "Namespace": "staging",
                "Capacity": "250Gi",
                "Status": "Pending"
            ]
        )
    ]
    let orphanReport = engine.analyze(
        pods: pods,
        nodes: nodes,
        pvcs: orphanPvc,
        workloads: [],
        window: .d30
    )
    let unboundRec = orphanReport.recommendations.first { $0.targetResource == "orphan-disk" }
    assert(unboundRec == nil, "Pending PVCs must not receive invented savings or delete advice")

    // Custom date range test
    let customReport = engine.analyze(
        pods: pods,
        nodes: nodes,
        pvcs: pvcs,
        workloads: [],
        window: .custom,
        customDays: 14.0,
        aggregation: .namespace
    )
    assert(customReport.window == .custom)
    assert(customReport.summary.windowSpendUSD > report.summary.windowSpendUSD, "14 days custom spend should be higher than 7 days spend")

    let providerReport = KubernetesCostReader.parseAllocationPayload(
        """
        {"code":200,"data":[
          {"shop":{"cpuCost":1.2,"ramCost":0.8,"pvCost":0.5,"networkCost":0.1,"totalCost":2.6,
                   "totalEfficiency":0.5,"cpuCoreUsageAverage":0.12,"ramByteUsageAverage":1048576,
                   "window":{"start":"2026-10-17T00:00:00Z","end":"2026-10-18T00:00:00Z"}},
           "__idle__":{"totalCost":0.4,"window":{"start":"2026-10-17T00:00:00Z","end":"2026-10-18T00:00:00Z"}}},
          {"shop":{"cpuCost":1.0,"ramCost":0.7,"pvCost":0.5,"networkCost":0.1,"totalCost":2.3,
                   "totalEfficiency":0.7,"cpuCoreUsageAverage":0.15,"ramByteUsageAverage":2097152,
                   "window":{"start":"2026-10-18T00:00:00Z","end":"2026-10-19T00:00:00Z"}}}
        ]}
        """,
        window: .d7,
        aggregation: .namespace,
        dataSource: .openCostAgent(endpoint: "opencost/opencost:9003", version: "")
    )
    assert(providerReport != nil)
    assert(providerReport?.dataSource.isLiveAgent == true)
    assert(providerReport?.rows.count == 1, "idle allocations must not appear as namespaces")
    assert(providerReport?.rows.first?.name == "shop")
    assert(abs((providerReport?.rows.first?.breakdown.totalCost ?? 0) - 4.9) < 0.0001)
    assert(abs((providerReport?.summary.windowSpendUSD ?? 0) - 5.3) < 0.0001)
    assert(abs((providerReport?.summary.totalIdleCostUSD ?? 0) - 0.4) < 0.0001)
    assert(providerReport?.timeSeries.count == 2, "provider history must retain real time buckets")
    assert(providerReport?.rows.first?.hasLiveUsage == true, "OpenCost usage samples must be preserved")
    assert(abs((providerReport?.rows.first?.efficiencyScore ?? 0) - 0.593877551) < 0.0001)

    let h24Report = KubernetesCostReader.parseAllocationPayload(
        """
        {"code":200,"data":[
          {"backend":{"cpuCost":0.5,"ramCost":0.5,"pvCost":0.0,"networkCost":0.0,"totalCost":1.0,
                     "window":{"start":"2026-10-18T00:00:00Z","end":"2026-10-19T00:00:00Z"}}}
        ]}
        """,
        window: .h24,
        aggregation: .namespace,
        dataSource: .openCostAgent(endpoint: "opencost/opencost:9003", version: "")
    )
    assert(h24Report != nil)
    assert(h24Report?.window == .h24)
    assert(abs((h24Report?.rows.first?.monthlyRunRateUSD ?? 0) - 30.0) < 0.0001, "24h monthly run rate must multiply by 30")

    // OpenCost Prometheus & StorageClass discovery tests
    let sampleServicesJSON = """
    {"items":[
      {"metadata":{"name":"prometheus-kube-prometheus-alertmanager","namespace":"monitoring","labels":{"app":"kube-prometheus-stack-alertmanager"}},
       "spec":{"clusterIP":"172.20.20.217","ports":[{"port":9093}]}},
      {"metadata":{"name":"prometheus-operated","namespace":"monitoring","labels":{"operated-prometheus":"true"}},
       "spec":{"clusterIP":"None","ports":[{"port":9090}]}},
      {"metadata":{"name":"prometheus-kube-prometheus-prometheus","namespace":"monitoring","labels":{"app":"kube-prometheus-stack-prometheus"}},
       "spec":{"clusterIP":"172.20.178.56","ports":[{"name":"http-web","port":9090}]}}
    ]}
    """
    let discoveredProm = KubernetesOpenCostSetupService.discoverPrometheusService(fromServicesJSON: sampleServicesJSON)
    assert(discoveredProm?.namespace == "monitoring")
    assert(discoveredProm?.serviceName == "prometheus-kube-prometheus-prometheus")
    assert(discoveredProm?.port == 9090)
    assert(discoveredProm?.inClusterURL == "http://prometheus-kube-prometheus-prometheus.monitoring.svc:9090")

    let sampleStorageClassJSON = """
    {"items":[
      {"metadata":{"name":"gp2","annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}},
      {"metadata":{"name":"gp3","annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}
    ]}
    """
    let storageInfo = KubernetesOpenCostSetupService.parseStorageClasses(fromJSON: sampleStorageClassJSON)
    assert(storageInfo.classes == ["gp2", "gp3"])
    assert(storageInfo.defaultClasses == ["gp2", "gp3"])
    assert(storageInfo.summary.contains("persistence.enabled=false"))

    if let prom = discoveredProm {
        let helm4Args = KubernetesOpenCostSetupService.helmUpgradeInstallArguments(
            clusterName: "prod-eks",
            prometheus: prom,
            isHelm4: true,
            dryRunServer: false
        )
        assert(helm4Args.contains("--rollback-on-failure"))
        assert(helm4Args.contains("opencost.prometheus.internal.serviceName=prometheus-kube-prometheus-prometheus"))
        assert(helm4Args.contains("opencost.prometheus.internal.namespaceName=monitoring"))
        assert(helm4Args.contains("opencost.exporter.persistence.enabled=false"))
        assert(helm4Args.contains("opencost.exporter.collectorDataSource.enabled=false"))
        assert(helm4Args.contains("opencost.mcp.enabled=false"))
    }

    let collectorArgs = KubernetesOpenCostSetupService.helmUpgradeInstallArguments(
        clusterName: "production-cluster",
        prometheus: nil,
        collectorStorageClass: "standard",
        isHelm4: false,
        dryRunServer: false
    )
    assert(collectorArgs.contains("opencost.prometheus.internal.enabled=false"))
    assert(collectorArgs.contains("opencost.exporter.collectorDataSource.enabled=true"))
    assert(collectorArgs.contains("opencost.exporter.persistence.storageClass=standard"))
    assert(collectorArgs.contains("opencost.exporter.persistence.size=1Gi"))

    runOpenCostSetupWorkflowTests(
        sampleServicesJSON: sampleServicesJSON,
        sampleStorageClassJSON: sampleStorageClassJSON,
        verifiedReport: providerReport!
    )
}

private final class MockOpenCostRunner: KubectlRunning, KubectlCommandBuilding, @unchecked Sendable {
    var hasPrometheus: Bool = true
    var recordedCommands: [KubectlCommand] = []
    private let servicesJSON: String
    private let storageClassJSON: String

    init(servicesJSON: String, storageClassJSON: String) {
        self.servicesJSON = servicesJSON
        self.storageClassJSON = storageClassJSON
    }

    func inspectionCommand(context: String, arguments: [String]) throws -> KubectlCommand {
        KubectlCommand(executablePath: "/usr/local/bin/kubectl", arguments: ["--context", context] + arguments)
    }

    func run(_ command: KubectlCommand, timeout: TimeInterval) async throws -> KubectlResult {
        recordedCommands.append(command)
        let args = command.arguments
        if command.executablePath.hasSuffix("helm") {
            if args.contains("version") {
                return KubectlResult(exitCode: 0, stdout: "v4.3.1+gc0d08d0\n", stderr: "")
            }
            if args.contains("--dry-run=server") {
                let sampleManifest = """
                NAME: opencost
                MANIFEST:
                ---
                # Source: opencost/templates/serviceaccount.yaml
                apiVersion: v1
                kind: ServiceAccount
                metadata:
                  name: opencost
                  namespace: opencost
                  labels:
                    helm.sh/chart: opencost-2.5.33
                    app.kubernetes.io/version: "1.121.3"
                ---
                # Source: opencost/templates/deployment.yaml
                apiVersion: apps/v1
                kind: Deployment
                metadata:
                  name: opencost
                  namespace: opencost
                spec:
                  template:
                    spec:
                      containers:
                        - image: ghcr.io/opencost/opencost:1.121.3@sha256:4cdd1732
                """
                return KubectlResult(exitCode: 0, stdout: sampleManifest, stderr: "")
            }
            return KubectlResult(exitCode: 0, stdout: "release \"opencost\" deployed\n", stderr: "")
        }
        if args.contains("can-i") {
            return KubectlResult(exitCode: 0, stdout: "yes\n", stderr: "")
        }
        if args.contains("services") {
            let payload = hasPrometheus ? servicesJSON : #"{"items":[]}"#
            return KubectlResult(exitCode: 0, stdout: payload, stderr: "")
        }
        if args.contains("pods") {
            let podsJSON = #"{"items":[{"metadata":{"name":"prometheus-prometheus-kube-prometheus-prometheus-0"},"status":{"phase":"Running"}}]}"#
            return KubectlResult(exitCode: 0, stdout: podsJSON, stderr: "")
        }
        if args.contains("storageclasses") {
            return KubectlResult(exitCode: 0, stdout: storageClassJSON, stderr: "")
        }
        if args.contains("rollout") {
            return KubectlResult(exitCode: 0, stdout: "deployment \"opencost\" successfully rolled out\n", stderr: "")
        }
        return KubectlResult(exitCode: 0, stdout: "{}", stderr: "")
    }
}

private struct MockVerifiedCostReader: KubernetesCostReading {
    let verifiedReport: FinOpsReport

    func report(
        context: KubernetesContextProfile,
        window: FinOpsTimeWindow,
        customStart: Date,
        customEnd: Date,
        aggregation: FinOpsAggregation
    ) async -> KubernetesCostReadResult {
        KubernetesCostReadResult(report: verifiedReport)
    }
}

private func runOpenCostSetupWorkflowTests(
    sampleServicesJSON: String,
    sampleStorageClassJSON: String,
    verifiedReport: FinOpsReport
) {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        let context = KubernetesContextProfile(
            contextName: "arn:aws:eks:eu-west-1:123456789012:cluster/prod-eks",
            clusterName: "prod-eks",
            userName: "admin",
            namespace: "default",
            kubeconfigPath: "/tmp/kubeconfig",
            providerType: .eks,
            environmentDetection: EnvironmentDetectionResult(type: .production, confidence: 1.0, source: "test")
        )
        let runner = MockOpenCostRunner(
            servicesJSON: sampleServicesJSON,
            storageClassJSON: sampleStorageClassJSON
        )
        let service = KubernetesOpenCostSetupService(
            runner: runner,
            costReader: MockVerifiedCostReader(verifiedReport: verifiedReport),
            helmPathResolver: { "/opt/homebrew/bin/helm" }
        )

        // 1. Missing Prometheus with ambiguous default storage blocks Collector safely.
        runner.hasPrometheus = false
        let blockedPreflight = await service.runPreflight(context: context)
        assert(!blockedPreflight.canProceedToInstall, "Preflight must block when Collector storage is ambiguous")
        assert(blockedPreflight.remediationSummary?.contains("Configure one default StorageClass") == true)
        let countBeforeBlockedInstall = runner.recordedCommands.count
        let blockedInstall = await service.installAndVerify(
            context: context,
            preflight: blockedPreflight,
            window: .d7,
            aggregation: .namespace,
            onStep: { _ in }
        )
        assert(!blockedInstall.success, "Blocked preflight must not execute partial installation")
        assert(runner.recordedCommands.count == countBeforeBlockedInstall, "No subprocess commands may run when preflight is blocked")

        let collectorRunner = MockOpenCostRunner(
            servicesJSON: sampleServicesJSON,
            storageClassJSON: #"{"items":[{"metadata":{"name":"standard","annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}]}"#
        )
        collectorRunner.hasPrometheus = false
        let collectorService = KubernetesOpenCostSetupService(
            runner: collectorRunner,
            costReader: MockVerifiedCostReader(verifiedReport: verifiedReport),
            helmPathResolver: { "/opt/homebrew/bin/helm" }
        )
        let collectorPreflight = await collectorService.runPreflight(context: context)
        assert(collectorPreflight.canProceedToInstall, "A single default StorageClass should enable Collector mode")
        assert(collectorPreflight.commandArgumentsPreview.flatMap { $0 }.contains("opencost.exporter.collectorDataSource.enabled=true"))

        assert(KubernetesOpenCostSetupService.sanitizedClusterIdentifier(from: "arn:aws:eks:eu-west-1:123456789012:cluster/prod-eks") == "prod-eks")

        // 2. Full preflight + approved install + live cost verification
        runner.hasPrometheus = true
        let readyPreflight = await service.runPreflight(context: context)
        assert(readyPreflight.canProceedToInstall, "Preflight should pass when Helm, RBAC, and Prometheus are ready")
        assert(readyPreflight.isProduction, "Production context must be flagged")
        assert(readyPreflight.serverDryRunVerified, "Preflight must verify server-side dry-run")
        assert(readyPreflight.chartVersion == "opencost-2.5.33")
        assert(readyPreflight.appVersion == "1.121.3")
        assert(readyPreflight.containerImage == "ghcr.io/opencost/opencost:1.121.3")
        assert(readyPreflight.plannedResources.count == 3, "Should parse resources from server dry-run manifest")
        assert(readyPreflight.commandArgumentsPreview.count == 4, "Should preview repo add, repo update, server dry-run, and install")

        let installResult = await service.installAndVerify(
            context: context,
            preflight: readyPreflight,
            window: .d7,
            aggregation: .namespace,
            onStep: { _ in }
        )
        assert(installResult.success, "Approved OpenCost installation should succeed")
        assert(installResult.verifiedReport != nil, "Post-install verification must return live FinOpsReport")
        assert(installResult.steps.count >= 5, "Should emit step logs for repo add, repo update, dry-run, install, rollout, and API verification")
        semaphore.signal()
    }
    semaphore.wait()
}
