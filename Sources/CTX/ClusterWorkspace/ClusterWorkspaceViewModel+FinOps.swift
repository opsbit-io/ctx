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

        let key = "\(context.id)-\(selectedNamespace.displayName)-\(finopsWindow.rawValue)-\(finopsAggregation.rawValue)-\(finopsPricing.providerName)-\(pods.count)-\(nodes.count)-\(pvcs.count)-\(workloads.count)-\(podsList?.loadedAt.timeIntervalSince1970 ?? 0)-\(telemetryLoadedAt?.timeIntervalSince1970 ?? 0)"

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
            aggregation: finopsAggregation
        )
        cachedFinOpsReport = report
        lastFinOpsCacheKey = key
        return report
    }

    /// Whether any of the underlying inventories powering the FinOps center are currently loading.
    var isLoadingFinOps: Bool {
        isLoading(section: .pods) || isLoading(section: .nodes) || isLoading(section: .storage) || isLoading(section: .workloads)
    }

    /// Loads the Kubernetes inventories required to compute FinOps cost allocations.
    func loadFinOpsResources(bypassCache: Bool = false) {
        if bypassCache {
            cachedFinOpsReport = nil
            lastFinOpsCacheKey = ""
        }
        let kinds: [KubernetesResourceKind] = [.pods, .nodes, .pvc, .workloads]
        for kind in kinds {
            loadResource(kind: kind, bypassCache: bypassCache)
        }
        loadTelemetry(force: bypassCache)
    }
}
