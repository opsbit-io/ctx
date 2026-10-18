import Foundation

// MARK: - Cluster FinOps Calculation & Optimization Engine

public struct ClusterFinOpsEngine: Sendable {
    public let pricing: CloudPricingProfile

    public init(pricing: CloudPricingProfile = .standard) {
        self.pricing = pricing
    }

    /// Generates a modeled allocation report from current cluster inventory and any
    /// current metrics supplied by the caller. Currency values are estimates unless
    /// an external verified cost source is provided.
    public func analyze(
        pods: [KubernetesResourceRow],
        nodes: [KubernetesResourceRow],
        pvcs: [KubernetesResourceRow],
        workloads: [KubernetesResourceRow],
        telemetry: ClusterTelemetryMetrics? = nil,
        window: FinOpsTimeWindow = .h24,
        customDays: Double? = nil,
        aggregation: FinOpsAggregation = .namespace,
        externalDataSource: FinOpsDataSourceStatus? = nil
    ) -> FinOpsReport {
        let activeDays: Double = (window == .custom && customDays != nil) ? max(0.1, customDays!) : window.daysFactor
        let hoursInWindow = 24.0 * activeDays
        let activeMonthlyMultiplier = 30.0 / activeDays

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
            let instanceType = node.cells["InstanceType"] ?? KubernetesGitOpsService.unknownValue

            let info = NodeCapacityInfo(
                id: node.id,
                name: nodeName,
                cores: max(0, cores),
                memoryGiB: max(0, memGiB),
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
            let hasLiveTelemetry: Bool
        }

        var podInfos: [PodCostInfo] = []
        var totalAllocatedCores: Double = 0
        var totalAllocatedMemGiB: Double = 0

        for pod in pods {
            let ns = pod.namespace ?? pod.cells["Namespace"] ?? "default"
            let nodeName = pod.cells["Node"] ?? ""
            let rawOwner = pod.cells["Workload"] ?? pod.cells["Owner"] ?? ""
            let workloadName = rawOwner.isEmpty ? pod.id : rawOwner

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

            podInfos.append(PodCostInfo(
                name: pod.id,
                namespace: ns,
                node: nodeName,
                workload: workloadName,
                requestedCores: reqCores,
                usedCores: usedCores,
                requestedMemGiB: reqMemGiB,
                usedMemGiB: usedMemGiB,
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
                let storageCost = (storageGiB * pricing.storageMonthlyPerGB / 30.0) * activeDays

                let groupAllocatedCost = cpuCost + memCost
                let shareOfAllocation = allocatedWindowCost > 0 ? (groupAllocatedCost / allocatedWindowCost) : 0
                let idleCost = totalIdleWindowCost * shareOfAllocation
                let totalRowCost = cpuCost + memCost + storageCost + idleCost

                let groupHasLive = members.contains(where: { $0.hasLiveTelemetry })
                let cpuEff = (groupHasLive && groupReqCores > 0) ? min(1.0, groupUsedCores / groupReqCores) : 0
                let memEff = (groupHasLive && groupReqMem > 0) ? min(1.0, groupUsedMem / groupReqMem) : 0
                let measuredRequestCost = cpuCost + memCost
                let measuredUsageCost = (groupUsedCores * pricing.cpuHourlyPerCore * hoursInWindow) +
                    (groupUsedMem * pricing.memoryHourlyPerGiB * hoursInWindow)
                let hasComparableUsage = groupHasLive && (measuredRequestCost > 0 || groupReqCores > 0 || groupReqMem > 0)
                let eff: Double
                if measuredRequestCost > 0 {
                    eff = min(1.0, measuredUsageCost / measuredRequestCost)
                } else if groupHasLive && (groupReqCores > 0 || groupReqMem > 0) {
                    let c = (groupReqCores > 0 ? 1.0 : 0.0) + (groupReqMem > 0 ? 1.0 : 0.0)
                    eff = c > 0 ? min(1.0, (cpuEff + memEff) / c) : 0
                } else {
                    eff = 0
                }

                let unutilizedCpuCost = groupHasLive ? max(0, cpuCost * (1.0 - cpuEff)) : 0
                let unutilizedMemCost = groupHasLive ? max(0, memCost * (1.0 - memEff)) : 0
                let rowWaste = unutilizedCpuCost + unutilizedMemCost
                let monthlyRun = totalRowCost * activeMonthlyMultiplier

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
                        networkCost: 0,
                        idleCost: idleCost,
                        totalCost: totalRowCost
                    ),
                    efficiencyScore: eff,
                    estimatedWasteUSD: rowWaste,
                    monthlyRunRateUSD: monthlyRun,
                    resourceKind: "Namespace",
                    hasLiveUsage: hasComparableUsage,
                    cpuCoresRequested: groupReqCores,
                    cpuCoresUsed: groupUsedCores,
                    memoryGiBRequested: groupReqMem,
                    memoryGiBUsed: groupUsedMem,
                    storageGiB: storageGiB
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
                let groupAllocatedCost = cpuCost + memCost
                let shareOfAllocation = allocatedWindowCost > 0 ? (groupAllocatedCost / allocatedWindowCost) : 0
                let idleCost = totalIdleWindowCost * shareOfAllocation
                let totalRowCost = cpuCost + memCost + idleCost

                let groupHasLive = members.contains(where: { $0.hasLiveTelemetry })
                let cpuEff = (groupHasLive && groupReqCores > 0) ? min(1.0, groupUsedCores / groupReqCores) : 0
                let memEff = (groupHasLive && groupReqMem > 0) ? min(1.0, groupUsedMem / groupReqMem) : 0
                let measuredRequestCost = cpuCost + memCost
                let measuredUsageCost = (groupUsedCores * pricing.cpuHourlyPerCore * hoursInWindow) +
                    (groupUsedMem * pricing.memoryHourlyPerGiB * hoursInWindow)
                let hasComparableUsage = groupHasLive && (measuredRequestCost > 0 || groupReqCores > 0 || groupReqMem > 0)
                let eff: Double
                if measuredRequestCost > 0 {
                    eff = min(1.0, measuredUsageCost / measuredRequestCost)
                } else if groupHasLive && (groupReqCores > 0 || groupReqMem > 0) {
                    let c = (groupReqCores > 0 ? 1.0 : 0.0) + (groupReqMem > 0 ? 1.0 : 0.0)
                    eff = c > 0 ? min(1.0, (cpuEff + memEff) / c) : 0
                } else {
                    eff = 0
                }

                let unutilizedCpuCost = groupHasLive ? max(0, cpuCost * (1.0 - cpuEff)) : 0
                let unutilizedMemCost = groupHasLive ? max(0, memCost * (1.0 - memEff)) : 0
                let rowWaste = unutilizedCpuCost + unutilizedMemCost
                let monthlyRun = totalRowCost * activeMonthlyMultiplier

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
                        networkCost: 0,
                        idleCost: idleCost,
                        totalCost: totalRowCost
                    ),
                    efficiencyScore: eff,
                    estimatedWasteUSD: rowWaste,
                    monthlyRunRateUSD: monthlyRun,
                    resourceKind: "Workload",
                    hasLiveUsage: hasComparableUsage,
                    cpuCoresRequested: groupReqCores,
                    cpuCoresUsed: groupUsedCores,
                    memoryGiBRequested: groupReqMem,
                    memoryGiBUsed: groupUsedMem,
                    storageGiB: 0
                ))
            }

        case .node:
            // ALWAYS build from live nodes in the cluster
            if !nodes.isEmpty {
                for node in nodes {
                    let nodeName = node.cells["Name"] ?? node.id
                    guard let info = nodeMap[node.id] ?? nodeMap[nodeName] else { continue }

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
                    let hasComparableUsage: Bool
                    if let cpuPct = info.cpuUsedPercent, let memPct = info.memUsedPercent {
                        let cpuCapacityCost = info.cores * pricing.cpuHourlyPerCore
                        let memoryCapacityCost = info.memoryGiB * pricing.memoryHourlyPerGiB
                        let capacityCost = cpuCapacityCost + memoryCapacityCost
                        if capacityCost > 0 {
                            hasComparableUsage = true
                            eff = ((cpuPct * cpuCapacityCost) + (memPct * memoryCapacityCost)) / capacityCost
                        } else if info.cores > 0 || info.memoryGiB > 0 {
                            hasComparableUsage = true
                            let c = (info.cores > 0 ? 1.0 : 0.0) + (info.memoryGiB > 0 ? 1.0 : 0.0)
                            eff = c > 0 ? min(1.0, (cpuPct + memPct) / c) : 0
                        } else {
                            hasComparableUsage = false
                            eff = 0
                        }
                    } else {
                        hasComparableUsage = false
                        eff = 0
                    }

                    let rowWaste = hasComparableUsage ? nodeTotalWindowCost * max(0, 1.0 - eff) : 0
                    let monthlyRun = totalRowCost * activeMonthlyMultiplier

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
                            networkCost: 0,
                            idleCost: idleCost,
                            totalCost: totalRowCost
                        ),
                        efficiencyScore: eff,
                        estimatedWasteUSD: rowWaste,
                        monthlyRunRateUSD: monthlyRun,
                        resourceKind: "Node",
                        hasLiveUsage: hasComparableUsage,
                        cpuCoresRequested: nodeReqCores,
                        cpuCoresUsed: (info.cpuUsedPercent ?? 0) * info.cores,
                        memoryGiBRequested: nodeReqMem,
                        memoryGiBUsed: (info.memUsedPercent ?? 0) * info.memoryGiB,
                        storageGiB: 0
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
                    let totalRowCost = cpuCost + memCost
                    let groupUsedCores = members.reduce(0.0) { $0 + $1.usedCores }
                    let groupUsedMem = members.reduce(0.0) { $0 + $1.usedMemGiB }
                    let measuredUsageCost = (groupUsedCores * pricing.cpuHourlyPerCore * hoursInWindow) +
                        (groupUsedMem * pricing.memoryHourlyPerGiB * hoursInWindow)
                    let hasComparableUsage = members.contains(where: { $0.hasLiveTelemetry }) && (totalRowCost > 0 || groupReqCores > 0 || groupReqMem > 0)
                    let eff: Double
                    if totalRowCost > 0 {
                        eff = min(1.0, measuredUsageCost / totalRowCost)
                    } else if hasComparableUsage && (groupReqCores > 0 || groupReqMem > 0) {
                        let cpuR = groupReqCores > 0 ? (groupUsedCores / groupReqCores) : 0
                        let memR = groupReqMem > 0 ? (groupUsedMem / groupReqMem) : 0
                        let c = (groupReqCores > 0 ? 1.0 : 0.0) + (groupReqMem > 0 ? 1.0 : 0.0)
                        eff = c > 0 ? min(1.0, (cpuR + memR) / c) : 0
                    } else {
                        eff = 0
                    }
                    let rowWaste = hasComparableUsage ? max(0, totalRowCost - measuredUsageCost) : 0
                    let monthlyRun = totalRowCost * activeMonthlyMultiplier

                    totalSpendAccumulator += totalRowCost
                    totalWasteAccumulator += rowWaste

                    allocationRows.append(FinOpsAllocationRow(
                        id: nodeName,
                        name: nodeName,
                        namespace: nil,
                        breakdown: FinOpsCostBreakdown(
                            cpuCost: cpuCost,
                            memoryCost: memCost,
                            storageCost: 0,
                            networkCost: 0,
                            idleCost: 0,
                            totalCost: totalRowCost
                        ),
                        efficiencyScore: eff,
                        estimatedWasteUSD: rowWaste,
                        monthlyRunRateUSD: monthlyRun,
                        resourceKind: "Node (pod assignment)",
                        hasLiveUsage: hasComparableUsage,
                        cpuCoresRequested: groupReqCores,
                        cpuCoresUsed: groupUsedCores,
                        memoryGiBRequested: groupReqMem,
                        memoryGiBUsed: groupUsedMem,
                        storageGiB: 0
                    ))
                }
            }
        }

        // Sort rows by spend descending (or by requested cores if unpriced)
        allocationRows.sort {
            if $0.breakdown.totalCost != $1.breakdown.totalCost {
                return $0.breakdown.totalCost > $1.breakdown.totalCost
            }
            return $0.cpuCoresRequested > $1.cpuCoresRequested
        }

        // If spend accumulator was 0, fall back to calculated cluster node baseline
        if totalSpendAccumulator <= 0 {
            totalSpendAccumulator = clusterWindowNodeCost
        }

        // A single current metrics sample cannot support a safe right-sizing change.
        // Recommendations stay empty until a verified historical source is integrated.
        let recommendations: [FinOpsRecommendation] = []

        // A current resource snapshot is not historical billing data. CTX leaves the
        // series empty until a real time-series source (OpenCost/Kubecost) supplies it.
        let timeSeries: [FinOpsTimeSeriesPoint] = []

        // 8. Overall Summary
        let totalMonthlyRunRate = totalSpendAccumulator * activeMonthlyMultiplier
        let potentialMonthlySavings = recommendations.reduce(0.0) { $0 + $1.monthlySavingsUSD }

        let totalUsedCores = podInfos.reduce(0.0) { $0 + $1.usedCores }
        let totalUsedMemGiB = podInfos.reduce(0.0) { $0 + $1.usedMemGiB }
        let totalComputeCost = allocationRows.reduce(0.0) { $0 + $1.breakdown.cpuCost }
        let totalMemoryCost = allocationRows.reduce(0.0) { $0 + $1.breakdown.memoryCost }
        let totalStorageCost = allocationRows.reduce(0.0) { $0 + $1.breakdown.storageCost }
        let totalIdleCost = allocationRows.reduce(0.0) { $0 + $1.breakdown.idleCost }

        let measuredRequestCost = (totalAllocatedCores * pricing.cpuHourlyPerCore * hoursInWindow) +
            (totalAllocatedMemGiB * pricing.memoryHourlyPerGiB * hoursInWindow)
        let measuredUsageCost = (totalUsedCores * pricing.cpuHourlyPerCore * hoursInWindow) +
            (totalUsedMemGiB * pricing.memoryHourlyPerGiB * hoursInWindow)
        let hasAnyLiveTelemetry = podInfos.contains(where: { $0.hasLiveTelemetry })
        let overallEfficiency: Double
        if hasAnyLiveTelemetry {
            if measuredRequestCost > 0 {
                overallEfficiency = min(1.0, measuredUsageCost / measuredRequestCost)
            } else if totalAllocatedCores > 0 || totalAllocatedMemGiB > 0 {
                let cpuRatio = totalAllocatedCores > 0 ? (totalUsedCores / totalAllocatedCores) : 0
                let memRatio = totalAllocatedMemGiB > 0 ? (totalUsedMemGiB / totalAllocatedMemGiB) : 0
                let count = (totalAllocatedCores > 0 ? 1.0 : 0.0) + (totalAllocatedMemGiB > 0 ? 1.0 : 0.0)
                overallEfficiency = count > 0 ? min(1.0, (cpuRatio + memRatio) / count) : 0
            } else {
                overallEfficiency = 0
            }
        } else {
            overallEfficiency = 0
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
