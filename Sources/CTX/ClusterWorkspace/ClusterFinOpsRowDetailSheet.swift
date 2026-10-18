import SwiftUI
import CTXCore

struct ClusterFinOpsRowDetailSheet: View {
    let row: FinOpsAllocationRow
    let report: FinOpsReport
    let hasCostPricing: Bool
    let formatCurrency: (Double) -> String
    let formatCores: (Double) -> String
    let formatGiB: (Double) -> String
    let efficiencyColor: (Double) -> Color
    let iconForKind: (String?) -> String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: iconForKind(row.resourceKind))
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(.title3.weight(.bold))
                        if let ns = row.namespace {
                            Text("Namespace / Scope: \(ns)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            if hasCostPricing {
                HStack(spacing: 16) {
                    detailStatBox(title: "TOTAL WINDOW SPEND", value: formatCurrency(row.breakdown.totalCost), tint: .primary)
                    detailStatBox(title: "MONTHLY RUN RATE", value: formatCurrency(row.monthlyRunRateUSD), tint: .blue)
                    detailStatBox(
                        title: "EFFICIENCY SCORE",
                        value: row.hasLiveUsage ? "\(Int(round(row.efficiencyScore * 100)))%" : "Unavailable",
                        tint: row.hasLiveUsage ? efficiencyColor(row.efficiencyScore) : .secondary
                    )
                    detailStatBox(title: "ESTIMATED WASTE", value: formatCurrency(row.estimatedWasteUSD), tint: .orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Component Cost Breakdown")
                        .font(.headline)

                    VStack(spacing: 6) {
                        detailBreakdownRow(name: "Compute (CPU)", cost: row.breakdown.cpuCost, total: row.breakdown.totalCost, color: .blue)
                        detailBreakdownRow(name: "Memory (RAM)", cost: row.breakdown.memoryCost, total: row.breakdown.totalCost, color: .purple)
                        detailBreakdownRow(name: "Storage (PVC)", cost: row.breakdown.storageCost, total: row.breakdown.totalCost, color: .orange)
                        detailBreakdownRow(name: "Attributed Idle Reserve", cost: row.breakdown.idleCost, total: row.breakdown.totalCost, color: .gray)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            } else {
                HStack(spacing: 16) {
                    detailStatBox(title: "CPU REQUESTED", value: formatCores(row.cpuCoresRequested), tint: .blue)
                    detailStatBox(title: "MEMORY REQUESTED", value: formatGiB(row.memoryGiBRequested), tint: .purple)
                    detailStatBox(
                        title: "EFFICIENCY SCORE",
                        value: row.hasLiveUsage ? "\(Int(round(row.efficiencyScore * 100)))%" : "Declared Only",
                        tint: row.hasLiveUsage ? efficiencyColor(row.efficiencyScore) : .secondary
                    )
                    detailStatBox(title: "BOUND STORAGE", value: row.storageGiB > 0 ? formatGiB(row.storageGiB) : "0 GiB", tint: .orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Verified Cluster Allocation")
                        .font(.headline)

                    VStack(spacing: 6) {
                        resourceDetailRow(
                            name: "Compute (CPU)",
                            declared: formatCores(row.cpuCoresRequested),
                            active: row.hasLiveUsage ? formatCores(row.cpuCoresUsed) : "Pending Telemetry",
                            color: .blue
                        )
                        resourceDetailRow(
                            name: "Memory (RAM)",
                            declared: formatGiB(row.memoryGiBRequested),
                            active: row.hasLiveUsage ? formatGiB(row.memoryGiBUsed) : "Pending Telemetry",
                            color: .purple
                        )
                        resourceDetailRow(
                            name: "Storage (PVC)",
                            declared: row.storageGiB > 0 ? formatGiB(row.storageGiB) : "None",
                            active: row.storageGiB > 0 ? "Bound Claim" : "No PVC",
                            color: .orange
                        )
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // Matching recommendations if any
            let relatedRecs = report.recommendations.filter {
                $0.targetResource == row.name || ($0.namespace != nil && $0.namespace == row.name)
            }
            if !relatedRecs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Related Optimization Opportunities")
                        .font(.headline)

                    ForEach(relatedRecs) { rec in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.title).font(.subheadline.weight(.semibold))
                                Text(rec.subtitle).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(hasCostPricing ? "Save \(formatCurrency(rec.monthlySavingsUSD))/mo" : rec.suggestedAllocation)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Spacer()
        }
        .padding(22)
        .frame(width: 580, height: 460)
    }

    private func detailStatBox(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailBreakdownRow(name: String, cost: Double, total: Double, color: Color) -> some View {
        let pct = total > 0 ? Int(round((cost / total) * 100)) : 0
        return HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.caption)
            Spacer()
            Text("\(formatCurrency(cost)) (\(pct)%)")
                .font(.caption.monospacedDigit())
        }
    }

    private func resourceDetailRow(name: String, declared: String, active: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.caption)
            Spacer()
            Text("Req: \(declared)  •  Used: \(active)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
