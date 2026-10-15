import CTXCore
import Foundation

public func runClusterFinOpsTests() {
    let engine = ClusterFinOpsEngine(pricing: .aws)

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
    assert(report.timeSeries.count >= 2, "Time series should have at least 2 points")

    // Workload aggregation test
    let workloadReport = engine.analyze(
        pods: pods,
        nodes: [],
        pvcs: [],
        workloads: [],
        window: .h24,
        aggregation: .workload
    )
    assert(workloadReport.aggregation == .workload)
    let wlRow = workloadReport.rows.first { $0.name == "api-service" }
    assert(wlRow != nil, "Workload row should exist")
    assert(wlRow?.namespace == "production")

    // Unbound PVC test
    let orphanPvc = [
        KubernetesResourceRow(
            id: "orphan-disk",
            cells: [
                "Namespace": "staging",
                "Capacity": "100Gi",
                "Status": "Pending"
            ]
        )
    ]
    let orphanReport = engine.analyze(
        pods: [],
        nodes: [],
        pvcs: orphanPvc,
        workloads: [],
        window: .d30
    )
    let unboundRec = orphanReport.recommendations.first { $0.targetResource == "orphan-disk" }
    assert(unboundRec != nil, "Unbound PVC recommendation should be generated")
    assert(unboundRec?.severity == .warning)
}
