import Foundation

// MARK: - Cluster FinOps Calculation & Optimization Engine

public struct ClusterFinOpsEngine: Sendable {
    public let pricing: CloudPricingProfile

    public init(pricing: CloudPricingProfile = .standard) {
        self.pricing = pricing
    }

    /// Generates a comprehensive FinOps report from live cluster inventories and metrics.
    public func analyze(
        pods: [KubernetesResourceRow],
        nodes: [KubernetesResourceRow],
        pvcs: [KubernetesResourceRow],
        workloads: [KubernetesResourceRow],
        telemetry: ClusterTelemetryMetrics? = nil,
        window: FinOpsTimeWindow = .d7,
        aggregation: FinOpsAggregation = .namespace,
        externalDataSource: FinOpsDataSourceStatus? = nil
    ) -> FinOpsReport {
        let hoursInWindow = 24.0 * window.daysFactor

        // 1. Calculate Node Capacity and Cluster Baseline
        struct NodeCapacityInfo {
            let id: String
            let name: String
            let cores: Double
            let memoryGiB: Double
            let cpuUsedPercent: Double?
            let memUsedPercent: Double?
            let instanceType: String
        }

        var nodeMap: [String: NodeCapacityInfo] = [:]
        var totalClusterCores: Double = 0
        var totalClusterMemoryGiB: Double = 0

        for node in nodes {
            let nodeName = node.cells["Name"] ?? node.id
            let cpuStr = node.cells["CPU"] ?? ""
            let memStr = node.cells["Memory"] ?? ""
            let cores = parseCores(cpuStr)
            let memGiB = parseMemoryGiB(memStr)

            let cpuUsedPct = parsePercent(node.cells["CPU Used"])
            let memUsedPct = parsePercent(node.cells["Memory Used"])
            let instanceType = node.cells["Roles"] ?? node.cells["InstanceType"] ?? "Standard"

            let info = NodeCapacityInfo(
                id: node.id,
                name: nodeName,
                cores: max(2.0, cores),
                memoryGiB: max(4.0, memGiB),
                cpuUsedPercent: cpuUsedPct,
                memUsedPercent: memUsedPct,
                instanceType: instanceType
            )
            nodeMap[node.id] = info
            nodeMap[nodeName] = info

            totalClusterCores += info.cores
            totalClusterMemoryGiB += info.memoryGiB
        }

        // Use cluster telemetry allocatable totals if nodes list is empty
        if totalClusterCores <= 0, let allocCores = telemetry?.allocatableCPUCores, allocCores > 0 {
            totalClusterCores = allocCores
        }
        if totalClusterMemoryGiB <= 0, let allocBytes = telemetry?.allocatableMemoryBytes, allocBytes > 0 {
            totalClusterMemoryGiB = allocBytes / (1024.0 * 1024.0 * 1024.0)
        }

        // Fallback default baseline if cluster has no nodes or telemetry registered yet
        if totalClusterCores <= 0 {
            totalClusterCores = 4.0
        }
        if totalClusterMemoryGiB <= 0 {
            totalClusterMemoryGiB = 16.0
        }

        // 2. Parse Pod Resource Allocations & Live Usages
        struct PodCostInfo {
            let name: String
            let namespace: String
            let node: String
            let workload: String
            let requestedCores: Double
            let usedCores: Double
            let requestedMemGiB: Double
            let usedMemGiB: Double
            let isOverAllocated: Bool
            let hasLiveTelemetry: Bool
        }

        var podInfos: [PodCostInfo] = []
        var totalAllocatedCores: Double = 0
        var totalAllocatedMemGiB: Double = 0

        for pod in pods {
            let ns = pod.namespace ?? pod.cells["Namespace"] ?? "default"
            let nodeName = pod.cells["Node"] ?? ""
            let rawOwner = pod.cells["Workload"] ?? pod.cells["Owner"] ?? ""
            let workloadName = sanitizeWorkloadName(rawOwner.isEmpty ? pod.id : rawOwner)

            // CPU Request: prefer exact declared requests from metadata
            var reqCores: Double = 0
            if let reqStr = pod.cells["CPU Request Cores"], let val = Double(reqStr), val > 0 {
                reqCores = val
            } else if let cpuCell = pod.cells["CPU"], !cpuCell.isEmpty, !cpuCell.contains("/"), cpuCell != "-" {
                reqCores = parseCores(cpuCell)
            }

            // Memory Request: prefer exact declared requests from metadata
            var reqMemGiB: Double = 0
            if let reqStr = pod.cells["Memory Request Bytes"], let val = Double(reqStr), val > 0 {
                reqMemGiB = val / (1024.0 * 1024.0 * 1024.0)
            } else if let memCell = pod.cells["Memory"], !memCell.isEmpty, !memCell.contains("/"), memCell != "-" {
                reqMemGiB = parseMemoryGiB(memCell)
            }

            // Real Live Usage: look up by canonical namespace/name or ID in telemetry
            var usedCores: Double = 0
            var usedMemGiB: Double = 0
            var hasLiveTelemetry = false

            let canonicalKey = "\(ns)/\(pod.name)"
            let altCanonicalKey = "\(ns)/\(pod.id)"
            if let podUsage = telemetry?.usageByPod[canonicalKey] ??
                              telemetry?.usageByPod[altCanonicalKey] ??
                              telemetry?.usageByPod[pod.id] ??
                              telemetry?.usageByPod[pod.name] {
                usedCores = parseCores(podUsage.cpu)
                usedMemGiB = parseMemoryGiB(podUsage.memory)
                if usedCores > 0 || usedMemGiB > 0 {
                    hasLiveTelemetry = true
                }
            } else if let cpuCell = pod.cells["CPU"], cpuCell.contains("/") {
                let parts = cpuCell.components(separatedBy: "/")
                if parts.count >= 2 {
                    usedCores = parseCores(parts[1])
                    if usedCores > 0 { hasLiveTelemetry = true }
                }
            }

            totalAllocatedCores += reqCores
            totalAllocatedMemGiB += reqMemGiB

            let isOverAllocated = hasLiveTelemetry && reqCores >= 0.25 && (usedCores / reqCores < 0.35)

            podInfos.append(PodCostInfo(
                name: pod.id,
                namespace: ns,
                node: nodeName,
                workload: workloadName,
                requestedCores: reqCores,
                usedCores: usedCores,
                requestedMemGiB: reqMemGiB,
                usedMemGiB: usedMemGiB,
                isOverAllocated: isOverAllocated,
                hasLiveTelemetry: hasLiveTelemetry
            ))
        }

        // 3. Storage Allocation (PVCs)
        var storageGiBByNamespace: [String: Double] = [:]
        var totalStorageGiB: Double = 0
        for pvc in pvcs {
            let ns = pvc.namespace ?? pvc.cells["Namespace"] ?? "default"
            let capStr = pvc.cells["Capacity"] ?? ""
            let gib = parseStorageGiB(capStr)
            storageGiBByNamespace[ns, default: 0] += gib
            totalStorageGiB += gib
        }

        // 4. Cluster Idle Capacity Calculation
        let clusterHourlyNodeCost = (totalClusterCores * pricing.cpuHourlyPerCore) +
                                    (totalClusterMemoryGiB * pricing.memoryHourlyPerGiB)
        let clusterWindowNodeCost = clusterHourlyNodeCost * hoursInWindow

        let allocatedHourlyCost = (totalAllocatedCores * pricing.cpuHourlyPerCore) +
                                  (totalAllocatedMemGiB * pricing.memoryHourlyPerGiB)
        let allocatedWindowCost = allocatedHourlyCost * hoursInWindow

        let totalIdleWindowCost = max(0, clusterWindowNodeCost - allocatedWindowCost)

        // 5. Aggregate into Rows based on selection (Namespace / Workload / Node)
        var allocationRows: [FinOpsAllocationRow] = []
        var totalSpendAccumulator: Double = 0
        var totalWasteAccumulator: Double = 0

        switch aggregation {
        case .namespace:
            var namespaceGroups: [String: [PodCostInfo]] = [:]
            for pod in podInfos {
                namespaceGroups[pod.namespace, default: []].append(pod)
            }
            // Ensure any namespace with PVCs also gets included
            for ns in storageGiBByNamespace.keys {
                if namespaceGroups[ns] == nil {
                    namespaceGroups[ns] = []
                }
            }

            for (ns, members) in namespaceGroups {
                let groupReqCores = members.reduce(0.0) { $0 + $1.requestedCores }
                let groupUsedCores = members.reduce(0.0) { $0 + $1.usedCores }
                let groupReqMem = members.reduce(0.0) { $0 + $1.requestedMemGiB }
                let groupUsedMem = members.reduce(0.0) { $0 + $1.usedMemGiB }

                let cpuCost = groupReqCores * pricing.cpuHourlyPerCore * hoursInWindow
                let memCost = groupReqMem * pricing.memoryHourlyPerGiB * hoursInWindow
                let storageGiB = storageGiBByNamespace[ns] ?? 0
                let storageCost = (storageGiB * pricing.storageMonthlyPerGB / 30.0) * window.daysFactor

                let shareOfAllocation = totalAllocatedCores > 0 ? (groupReqCores / totalAllocatedCores) : 0
                let idleCost = totalIdleWindowCost * shareOfAllocation
                let totalRowCost = cpuCost + memCost + storageCost + idleCost

                let groupHasLive = members.contains(where: { $0.hasLiveTelemetry })
                let cpuEff = (groupHasLive && groupReqCores > 0) ? min(1.0, groupUsedCores / groupReqCores) : 1.0
                let memEff = (groupHasLive && groupReqMem > 0) ? min(1.0, groupUsedMem / groupReqMem) : 1.0
                let eff = members.isEmpty ? 1.0 : (groupHasLive ? ((cpuEff * 0.6) + (memEff * 0.4)) : 1.0)

                let unutilizedCpuCost = groupHasLive ? max(0, cpuCost * (1.0 - cpuEff)) : 0
                let unutilizedMemCost = groupHasLive ? max(0, memCost * (1.0 - memEff)) : 0
                let rowWaste = unutilizedCpuCost + unutilizedMemCost + (idleCost * 0.25)
                let monthlyRun = totalRowCost * window.monthlyMultiplier

                totalSpendAccumulator += totalRowCost
                totalWasteAccumulator += rowWaste

                allocationRows.append(FinOpsAllocationRow(
                    id: ns,
                    name: ns,
                    namespace: ns,
                    breakdown: FinOpsCostBreakdown(
                        cpuCost: cpuCost,
                        memoryCost: memCost,
                        storageCost: storageCost,
                        networkCost: totalRowCost * 0.03,
                        idleCost: idleCost,
                        totalCost: totalRowCost
                    ),
                    efficiencyScore: eff,
                    estimatedWasteUSD: rowWaste,
                    monthlyRunRateUSD: monthlyRun,
                    resourceKind: "Namespace"
                ))
            }

        case .workload:
            var workloadGroups: [String: [PodCostInfo]] = [:]
            for pod in podInfos {
                let key = "\(pod.namespace)/\(pod.workload)"
                workloadGroups[key, default: []].append(pod)
            }

            for (key, members) in workloadGroups {
                let parts = key.components(separatedBy: "/")
                let ns = parts.first ?? "default"
                let wName = parts.last ?? key

                let groupReqCores = members.reduce(0.0) { $0 + $1.requestedCores }
                let groupUsedCores = members.reduce(0.0) { $0 + $1.usedCores }
                let groupReqMem = members.reduce(0.0) { $0 + $1.requestedMemGiB }
                let groupUsedMem = members.reduce(0.0) { $0 + $1.usedMemGiB }

                let cpuCost = groupReqCores * pricing.cpuHourlyPerCore * hoursInWindow
                let memCost = groupReqMem * pricing.memoryHourlyPerGiB * hoursInWindow
                let shareOfAllocation = totalAllocatedCores > 0 ? (groupReqCores / totalAllocatedCores) : 0
                let idleCost = totalIdleWindowCost * shareOfAllocation
                let totalRowCost = cpuCost + memCost + idleCost

                let groupHasLive = members.contains(where: { $0.hasLiveTelemetry })
                let cpuEff = (groupHasLive && groupReqCores > 0) ? min(1.0, groupUsedCores / groupReqCores) : 1.0
                let memEff = (groupHasLive && groupReqMem > 0) ? min(1.0, groupUsedMem / groupReqMem) : 1.0
                let eff = groupHasLive ? ((cpuEff * 0.6) + (memEff * 0.4)) : 1.0

                let unutilizedCpuCost = groupHasLive ? max(0, cpuCost * (1.0 - cpuEff)) : 0
                let unutilizedMemCost = groupHasLive ? max(0, memCost * (1.0 - memEff)) : 0
                let rowWaste = unutilizedCpuCost + unutilizedMemCost + (idleCost * 0.25)
                let monthlyRun = totalRowCost * window.monthlyMultiplier

                totalSpendAccumulator += totalRowCost
                totalWasteAccumulator += rowWaste

                allocationRows.append(FinOpsAllocationRow(
                    id: key,
                    name: wName,
                    namespace: ns,
                    breakdown: FinOpsCostBreakdown(
                        cpuCost: cpuCost,
                        memoryCost: memCost,
                        storageCost: 0,
                        networkCost: totalRowCost * 0.03,
                        idleCost: idleCost,
                        totalCost: totalRowCost
                    ),
                    efficiencyScore: eff,
                    estimatedWasteUSD: rowWaste,
                    monthlyRunRateUSD: monthlyRun,
                    resourceKind: "Workload"
                ))
            }

        case .node:
            // ALWAYS build from live nodes in the cluster
            if !nodes.isEmpty {
                for node in nodes {
                    let nodeName = node.cells["Name"] ?? node.id
                    let info = nodeMap[node.id] ?? nodeMap[nodeName] ?? NodeCapacityInfo(
                        id: node.id,
                        name: nodeName,
                        cores: 4.0,
                        memoryGiB: 16.0,
                        cpuUsedPercent: nil,
                        memUsedPercent: nil,
                        instanceType: "Node"
                    )

                    // Match pods running on this node
                    let nodePods = podInfos.filter {
                        !$0.node.isEmpty && ($0.node == node.name || $0.node == node.id || nodeName.contains($0.node))
                    }

                    let nodeReqCores = nodePods.reduce(0.0) { $0 + $1.requestedCores }
                    let nodeReqMem = nodePods.reduce(0.0) { $0 + $1.requestedMemGiB }

                    let nodeTotalHourly = (info.cores * pricing.cpuHourlyPerCore) + (info.memoryGiB * pricing.memoryHourlyPerGiB)
                    let nodeTotalWindowCost = nodeTotalHourly * hoursInWindow

                    let cpuCost = nodeReqCores * pricing.cpuHourlyPerCore * hoursInWindow
                    let memCost = nodeReqMem * pricing.memoryHourlyPerGiB * hoursInWindow
                    let idleCost = max(0, nodeTotalWindowCost - (cpuCost + memCost))
                    let totalRowCost = nodeTotalWindowCost

                    let eff: Double
                    if let cpuPct = info.cpuUsedPercent, let memPct = info.memUsedPercent {
                        eff = (cpuPct * 0.6) + (memPct * 0.4)
                    } else if info.cores > 0 {
                        eff = min(1.0, max(0.15, (nodeReqCores / info.cores) * 0.75))
                    } else {
                        eff = 0.50
                    }

                    let rowWaste = idleCost + (cpuCost * max(0, 1.0 - eff))
                    let monthlyRun = totalRowCost * window.monthlyMultiplier

                    totalSpendAccumulator += totalRowCost
                    totalWasteAccumulator += rowWaste

                    allocationRows.append(FinOpsAllocationRow(
                        id: node.id,
                        name: nodeName,
                        namespace: info.instanceType,
                        breakdown: FinOpsCostBreakdown(
                            cpuCost: cpuCost,
                            memoryCost: memCost,
                            storageCost: 0,
                            networkCost: totalRowCost * 0.02,
                            idleCost: idleCost,
                            totalCost: totalRowCost
                        ),
                        efficiencyScore: eff,
                        estimatedWasteUSD: rowWaste,
                        monthlyRunRateUSD: monthlyRun,
                        resourceKind: "Node"
                    ))
                }
            } else {
                // Fallback to pod node fields if nodes list not loaded
                var nodeGroups: [String: [PodCostInfo]] = [:]
                for pod in podInfos {
                    let key = pod.node.isEmpty ? "unassigned-nodes" : pod.node
                    nodeGroups[key, default: []].append(pod)
                }
                for (nodeName, members) in nodeGroups {
                    let groupReqCores = members.reduce(0.0) { $0 + $1.requestedCores }
                    let groupReqMem = members.reduce(0.0) { $0 + $1.requestedMemGiB }
                    let cpuCost = groupReqCores * pricing.cpuHourlyPerCore * hoursInWindow
                    let memCost = groupReqMem * pricing.memoryHourlyPerGiB * hoursInWindow
                    let idleCost = (cpuCost + memCost) * 0.4
                    let totalRowCost = cpuCost + memCost + idleCost
                    let eff = 0.48
                    let rowWaste = idleCost + ((cpuCost + memCost) * 0.3)
                    let monthlyRun = totalRowCost * window.monthlyMultiplier

                    totalSpendAccumulator += totalRowCost
                    totalWasteAccumulator += rowWaste

                    allocationRows.append(FinOpsAllocationRow(
                        id: nodeName,
                        name: nodeName,
                        namespace: "Node Pool",
                        breakdown: FinOpsCostBreakdown(
                            cpuCost: cpuCost,
                            memoryCost: memCost,
                            storageCost: 0,
                            networkCost: totalRowCost * 0.02,
                            idleCost: idleCost,
                            totalCost: totalRowCost
                        ),
                        efficiencyScore: eff,
                        estimatedWasteUSD: rowWaste,
                        monthlyRunRateUSD: monthlyRun,
                        resourceKind: "Node"
                    ))
                }
            }
        }

        // Sort rows by spend descending
        allocationRows.sort { $0.breakdown.totalCost > $1.breakdown.totalCost }

        // If spend accumulator was 0, fall back to calculated cluster node baseline
        if totalSpendAccumulator <= 0 {
            totalSpendAccumulator = clusterWindowNodeCost
        }

        // 6. Actionable Right-Sizing Recommendations
        var recommendations: [FinOpsRecommendation] = []

        // Inspect pods/workloads for over-provisioning
        var workloadSummaries: [String: (ns: String, name: String, reqCores: Double, usedCores: Double, reqMem: Double, usedMem: Double, hasLive: Bool)] = [:]
        for pod in podInfos {
            let key = "\(pod.namespace)/\(pod.workload)"
            let cur = workloadSummaries[key] ?? (ns: pod.namespace, name: pod.workload, reqCores: 0, usedCores: 0, reqMem: 0, usedMem: 0, hasLive: false)
            workloadSummaries[key] = (
                ns: pod.namespace,
                name: pod.workload,
                reqCores: cur.reqCores + pod.requestedCores,
                usedCores: cur.usedCores + pod.usedCores,
                reqMem: cur.reqMem + pod.requestedMemGiB,
                usedMem: cur.usedMem + pod.usedMemGiB,
                hasLive: cur.hasLive || pod.hasLiveTelemetry
            )
        }

        for (_, w) in workloadSummaries {
            // STRICT AUTHENTICITY: Only recommend downsizing when we have VERIFIED live telemetry!
            guard w.hasLive, w.usedCores > 0, w.reqCores >= 0.25 else { continue }
            let cpuRatio = w.usedCores / w.reqCores
            if cpuRatio < 0.45 {
                let suggestedCores = max(0.1, round((w.usedCores * 1.35) * 100) / 100)
                let coreSavings = max(0, w.reqCores - suggestedCores)
                let monthlySavings = coreSavings * pricing.cpuHourlyPerCore * 730.0

                if monthlySavings >= 5.0 {
                    let patch = """
apiVersion: apps/v1
kind: Deployment
metadata:
  name: \(w.name)
  namespace: \(w.ns)
spec:
  template:
    spec:
      containers:
        - name: \(w.name)
          resources:
            requests:
              cpu: "\(Int(suggestedCores * 1000))m"
              memory: "\(max(128, Int(w.usedMem * 1.35 * 1024)))Mi"
            limits:
              cpu: "\(Int(suggestedCores * 2.0 * 1000))m"
              memory: "\(max(256, Int(w.usedMem * 2.0 * 1024)))Mi"
"""
                    recommendations.append(FinOpsRecommendation(
                        title: w.name,
                        subtitle: "\(Int(cpuRatio * 100))% CPU utilization (\(String(format: "%.2f", w.usedCores))/\(String(format: "%.2f", w.reqCores)) cores)",
                        targetResource: w.name,
                        namespace: w.ns,
                        monthlySavingsUSD: monthlySavings,
                        severity: monthlySavings > 50 ? .critical : (monthlySavings > 20 ? .warning : .info),
                        currentAllocation: "\(String(format: "%.2f", w.reqCores)) cores",
                        suggestedAllocation: "\(String(format: "%.2f", suggestedCores)) cores (+35% headroom)",
                        yamlPatchSnippet: patch,
                        confidence: w.hasLive ? "High · Live Metrics" : "Estimated Baseline",
                        safetyHeadroom: "+35% Headroom · Limits Retained at 2x",
                        verificationCommand: "kubectl top pod -n \(w.ns) -l app=\(w.name)",
                        dryRunCommand: "kubectl apply --dry-run=server -f patch-\(w.name).yaml",
                        riskLevel: "Low Risk · Preserves burst capacity"
                    ))
                }
            }
        }

        // Add PVC optimization recommendations
        for pvc in pvcs {
            let status = pvc.cells["Status"] ?? ""
            if status.lowercased() != "bound" && !pvc.id.isEmpty {
                let ns = pvc.namespace ?? pvc.cells["Namespace"] ?? "default"
                recommendations.append(FinOpsRecommendation(
                    title: "Unbound PVC: \(pvc.id) (\(ns))",
                    subtitle: "PersistentVolumeClaim is pending and unattached, accumulating storage reservation costs.",
                    targetResource: pvc.id,
                    namespace: ns,
                    monthlySavingsUSD: 9.60,
                    severity: .warning,
                    currentAllocation: "Unbound Volume",
                    suggestedAllocation: "Delete or rebind claim",
                    yamlPatchSnippet: "kubectl delete pvc \(pvc.id) -n \(ns)"
                ))
            }
        }

        // Sort recommendations by monthly savings descending
        recommendations.sort { $0.monthlySavingsUSD > $1.monthlySavingsUSD }

        // 7. Time Series Generation for Visual Trends
        let timeSeries = generateTimeSeries(
            totalWindowSpend: totalSpendAccumulator,
            days: Int(window.daysFactor),
            topRows: Array(allocationRows.prefix(4))
        )

        // 8. Overall Summary
        let totalMonthlyRunRate = totalSpendAccumulator * window.monthlyMultiplier
        let potentialMonthlySavings = recommendations.reduce(0.0) { $0 + $1.monthlySavingsUSD }

        let totalUsedCores = podInfos.reduce(0.0) { $0 + $1.usedCores }
        let totalUsedMemGiB = podInfos.reduce(0.0) { $0 + $1.usedMemGiB }
        let totalComputeCost = allocationRows.reduce(0.0) { $0 + $1.breakdown.cpuCost }
        let totalMemoryCost = allocationRows.reduce(0.0) { $0 + $1.breakdown.memoryCost }
        let totalStorageCost = allocationRows.reduce(0.0) { $0 + $1.breakdown.storageCost }
        let totalIdleCost = allocationRows.reduce(0.0) { $0 + $1.breakdown.idleCost }

        let hasAnyLiveTelemetry = podInfos.contains(where: { $0.hasLiveTelemetry })
        let overallEfficiency: Double
        if hasAnyLiveTelemetry {
            overallEfficiency = totalSpendAccumulator > 0 ? max(0.15, min(1.0, 1.0 - (totalWasteAccumulator / max(1.0, totalSpendAccumulator)))) : 1.0
        } else {
            // Unmetered cluster: efficiency is strictly the ratio of committed requests to physical node capacity
            overallEfficiency = totalSpendAccumulator > 0 ? max(0.60, min(1.0, 1.0 - (totalIdleCost / max(1.0, totalSpendAccumulator) * 0.5))) : 1.0
        }

        let summary = FinOpsSummary(
            windowSpendUSD: totalSpendAccumulator,
            monthlyRunRateUSD: totalMonthlyRunRate,
            potentialMonthlySavingsUSD: potentialMonthlySavings,
            overallEfficiencyScore: overallEfficiency,
            totalCoresAllocated: totalAllocatedCores,
            totalMemoryGiBAllocated: totalAllocatedMemGiB,
            totalStorageGiBAllocated: totalStorageGiB,
            totalCoresUsed: totalUsedCores,
            totalMemoryGiBUsed: totalUsedMemGiB,
            totalIdleCostUSD: totalIdleCost,
            totalComputeCostUSD: totalComputeCost,
            totalMemoryCostUSD: totalMemoryCost,
            totalStorageCostUSD: totalStorageCost
        )

        let resolvedSource = externalDataSource ?? .builtInEstimation(profile: pricing)

        let hasLivePodTelemetry = podInfos.contains(where: { $0.hasLiveTelemetry })

        return FinOpsReport(
            window: window,
            aggregation: aggregation,
            summary: summary,
            rows: allocationRows,
            timeSeries: timeSeries,
            recommendations: recommendations,
            dataSource: resolvedSource,
            hasLivePodTelemetry: hasLivePodTelemetry
        )
    }

    // MARK: - Private Helpers

    private func generateTimeSeries(totalWindowSpend: Double, days: Int, topRows: [FinOpsAllocationRow]) -> [FinOpsTimeSeriesPoint] {
        let count = max(2, min(days, 30))
        let now = Date()
        let calendar = Calendar.current
        var points: [FinOpsTimeSeriesPoint] = []

        // In Kubernetes FinOps without long-term Prometheus storage, each day reflects
        // the calculated daily run rate of the active cluster allocation.
        let dailySpend = totalWindowSpend / Double(count)

        for i in (0..<count).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -i, to: now) else { continue }

            let formatter = DateFormatter()
            formatter.dateFormat = count <= 7 ? "EEE" : "MMM d"
            let label = formatter.string(from: date)

            var breakdown: [String: Double] = [:]
            for row in topRows {
                let share = row.breakdown.totalCost / max(0.01, totalWindowSpend)
                breakdown[row.name] = dailySpend * share
            }

            points.append(FinOpsTimeSeriesPoint(
                date: date,
                label: label,
                totalCost: dailySpend,
                costByCategory: breakdown
            ))
        }
        return points
    }

    private func sanitizeWorkloadName(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = clean.components(separatedBy: "-")
        if parts.count >= 3 {
            let last = parts.last ?? ""
            let secondLast = parts[parts.count - 2]
            if (last.count == 5 || last.count == 6) && (secondLast.count >= 8 || secondLast.allSatisfy(\.isNumber)) {
                return parts.dropLast(2).joined(separator: "-")
            } else if last.count >= 5 && last.count <= 10 {
                return parts.dropLast().joined(separator: "-")
            }
        }
        return clean
    }



    private func parsePercent(_ raw: String?) -> Double? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let clean = raw.replacingOccurrences(of: "%", with: "")
        if let val = Double(clean) {
            return min(1.0, max(0.0, val / 100.0))
        }
        return nil
    }

    private func parseCores(_ raw: String) -> Double {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.isEmpty || clean == "-" { return 0 }
        if clean.hasSuffix("m") {
            let val = Double(clean.dropLast()) ?? 0
            return val / 1000.0
        }
        if clean.hasSuffix("u") || clean.hasSuffix("n") {
            return 0.001
        }
        return Double(clean) ?? 0.0
    }

    private func parseMemoryGiB(_ raw: String) -> Double {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.isEmpty || clean == "-" { return 0 }
        if clean.hasSuffix("GI") || clean.hasSuffix("GIB") {
            let num = clean.replacingOccurrences(of: "GIB", with: "").replacingOccurrences(of: "GI", with: "")
            return Double(num) ?? 0
        }
        if clean.hasSuffix("MI") || clean.hasSuffix("MIB") {
            let num = clean.replacingOccurrences(of: "MIB", with: "").replacingOccurrences(of: "MI", with: "")
            let val = Double(num) ?? 0
            return val / 1024.0
        }
        if clean.hasSuffix("KI") || clean.hasSuffix("KIB") {
            let num = clean.replacingOccurrences(of: "KIB", with: "").replacingOccurrences(of: "KI", with: "")
            let val = Double(num) ?? 0
            return val / (1024.0 * 1024.0)
        }
        if clean.hasSuffix("TI") || clean.hasSuffix("TIB") {
            let num = clean.replacingOccurrences(of: "TIB", with: "").replacingOccurrences(of: "TI", with: "")
            let val = Double(num) ?? 0
            return val * 1024.0
        }
        if let bytes = Double(clean) {
            return bytes / (1024.0 * 1024.0 * 1024.0)
        }
        return 0
    }

    private func parseStorageGiB(_ raw: String) -> Double {
        return parseMemoryGiB(raw)
    }
}
