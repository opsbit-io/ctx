import SwiftUI
import Charts
import CTXCore

struct ClusterFinOpsView: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel
    @State private var showingMethodologyModal = false
    @State private var showingOpenCostInfo = false
    @State private var selectedRecommendation: FinOpsRecommendation?
    @State private var selectedRowDetail: FinOpsAllocationRow?
    @State private var copiedYAML = false
    @State private var copiedVerifyCommand = false
    @State private var copiedDryRunCommand = false
    @State private var sortColumn: SortColumn = .totalSpend
    @State private var sortAscending = false
    @State private var availableWidth: CGFloat = 1000
    @State private var finopsKindFilter: String = "All"
    @State private var finopsMinSpendFilter: Double = 0
    @State private var finopsEfficiencyFilter: String = "All"
    @State private var customColumnWidths: [SortColumn: CGFloat] = [:]

    enum SortColumn: String, CaseIterable {
        case name = "Name"
        case cpu = "CPU"
        case memory = "Memory"
        case storage = "Storage"
        case idle = "Idle Share"
        case totalSpend = "Total Spend"
        case monthlyRun = "Monthly Run"
        case efficiency = "Efficiency"
    }

    private var report: FinOpsReport {
        viewModel.currentFinOpsReport
    }

    private var sortedAndFilteredRows: [FinOpsAllocationRow] {
        let q = viewModel.finopsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = report.rows.filter { row in
            if !q.isEmpty {
                let matches = row.name.lowercased().contains(q) ||
                    (row.namespace?.lowercased().contains(q) ?? false) ||
                    (row.resourceKind?.lowercased().contains(q) ?? false)
                if !matches { return false }
            }
            if finopsKindFilter != "All" {
                if (row.resourceKind?.lowercased() ?? "") != finopsKindFilter.lowercased() {
                    return false
                }
            }
            if finopsMinSpendFilter > 0 {
                if row.breakdown.totalCost < finopsMinSpendFilter {
                    return false
                }
            }
            if finopsEfficiencyFilter == "Low" && row.efficiencyScore >= 0.5 {
                return false
            } else if finopsEfficiencyFilter == "Optimal" && row.efficiencyScore < 0.8 {
                return false
            }
            return true
        }

        return base.sorted { a, b in
            let result: Bool
            switch sortColumn {
            case .name:
                result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .cpu:
                result = a.breakdown.cpuCost < b.breakdown.cpuCost
            case .memory:
                result = a.breakdown.memoryCost < b.breakdown.memoryCost
            case .storage:
                result = a.breakdown.storageCost < b.breakdown.storageCost
            case .idle:
                result = a.breakdown.idleCost < b.breakdown.idleCost
            case .totalSpend:
                result = a.breakdown.totalCost < b.breakdown.totalCost
            case .monthlyRun:
                result = a.monthlyRunRateUSD < b.monthlyRunRateUSD
            case .efficiency:
                result = a.efficiencyScore < b.efficiencyScore
            }
            return sortAscending ? result : !result
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerBar
            kpiCardGrid
            analyticsCockpitSection
            if !report.recommendations.isEmpty {
                recommendationsSection
            }
            allocationTableSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.width, initial: true) { _, width in
                        guard abs(width - availableWidth) > 1 else { return }
                        availableWidth = width
                    }
            }
        )
        .onAppear {
            viewModel.loadFinOpsResources()
        }
        .sheet(item: $selectedRecommendation) { rec in
            recommendationDetailSheet(rec)
        }
        .sheet(item: $selectedRowDetail) { row in
            rowDetailSheet(row)
        }
        .sheet(isPresented: $showingMethodologyModal) {
            methodologyAndSafetySheet
        }
        .popover(isPresented: $showingOpenCostInfo, arrowEdge: .bottom) {
            openCostPopover
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Title + Verification Badge + Methodology CTA + Cloud Provider + Refresh
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.accentColor)

                    Text("FinOps & Costs")
                        .font(.system(size: 18, weight: .bold))

                    dataAuthenticityBadge
                }

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    // Methodology & Safety Button
                    Button {
                        showingMethodologyModal = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "shield.checkerboard")
                                .font(.system(size: 11))
                            Text("Methodology & Safety")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    cloudProfileMenu
                }
            }

            // Row 2: Unified Pill Controls (Aggregation Dimension + Time Window + Search)
            HStack(spacing: 12) {
                // Aggregation Dimension Pills (Namespaces | Workloads | Nodes)
                HStack(spacing: 4) {
                    ForEach(FinOpsAggregation.allCases) { agg in
                        let isSelected = viewModel.finopsAggregation == agg
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.finopsAggregation = agg
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: iconForKind(agg.rawValue.capitalized))
                                    .font(.system(size: 10))
                                Text(agg.displayName)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(
                                isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .overlay {
                                if isSelected {
                                    Capsule().stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()
                    .frame(height: 16)

                // Time Window Pills (24 Hours | 7 Days | 30 Days | Month to Date)
                HStack(spacing: 4) {
                    ForEach(FinOpsTimeWindow.allCases) { win in
                        let isSelected = viewModel.finopsWindow == win
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.finopsWindow = win
                            }
                        } label: {
                            Text(win.shortName)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4.5)
                                .background(
                                    isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                                    in: Capsule()
                                )
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .overlay {
                                    if isSelected {
                                        Capsule().stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Compact Search Field
                CTXSearchField(placeholder: "Search allocation...", text: $viewModel.finopsSearchText)
                    .frame(width: 200)
            }
        }
    }

    private var cloudProfileMenu: some View {
        Menu {
            Button("AWS (m6i / gp3 standard)") {
                viewModel.finopsPricing = .aws
            }
            Button("Google Cloud (n2 / pd-standard)") {
                viewModel.finopsPricing = .gcp
            }
            Button("Microsoft Azure (Dsv5 / SSD)") {
                viewModel.finopsPricing = .azure
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cloud.fill")
                    .font(.caption2)
                Text(viewModel.finopsPricing.providerName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var dataAuthenticityBadge: some View {
        Button {
            showingMethodologyModal = true
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(report.hasLivePodTelemetry ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(report.hasLivePodTelemetry ? "Live Metrics Verified" : "Baseline Requests")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background((report.hasLivePodTelemetry ? Color.green : Color.orange).opacity(0.08), in: Capsule())
            .overlay {
                Capsule().stroke((report.hasLivePodTelemetry ? Color.green : Color.orange).opacity(0.25), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .help(report.hasLivePodTelemetry ? "Real pod usage is tracked from live cluster metrics." : "Costs are calculated from declared resource requests. Click to view methodology.")
    }

    // MARK: - Hero KPI Cards

    private var kpiColumns: [GridItem] {
        if availableWidth < 760 {
            return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        } else {
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }

    private var kpiCardGrid: some View {
        LazyVGrid(columns: kpiColumns, spacing: 12) {
            finopsKpiCard(
                title: "MONTHLY RUN RATE",
                value: formatCurrency(report.summary.monthlyRunRateUSD),
                subtitle: "Est. annualized \(formatCurrency(report.summary.monthlyRunRateUSD * 12))",
                icon: "chart.line.uptrend.xyaxis",
                tint: .blue
            )
            finopsKpiCard(
                title: "WINDOW SPEND (\(viewModel.finopsWindow.rawValue.uppercased()))",
                value: formatCurrency(report.summary.windowSpendUSD),
                subtitle: "Compute, memory, storage & idle",
                icon: "creditcard.fill",
                tint: .indigo
            )
            finopsKpiCard(
                title: "RESOURCE EFFICIENCY",
                value: "\(Int(round(report.summary.overallEfficiencyScore * 100)))%",
                subtitle: efficiencySubtitle(report.summary.overallEfficiencyScore),
                icon: "gauge.with.needle.fill",
                tint: efficiencyColor(report.summary.overallEfficiencyScore)
            )
            finopsKpiCard(
                title: "POTENTIAL SAVINGS",
                value: formatCurrency(report.summary.potentialMonthlySavingsUSD) + " / mo",
                subtitle: "\(report.recommendations.count) safe optimizations identified",
                icon: "sparkles",
                tint: .green
            )
        }
    }

    private func finopsKpiCard(title: String, value: String, subtitle: String, icon: String, tint: Color) -> some View {
        CTXGlassPanel(padding: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .fixedSize()

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                        .lineLimit(1)

                    Text(value)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Analytics Cockpit Section

    @ViewBuilder
    private var analyticsCockpitSection: some View {
        if availableWidth < 920 {
            VStack(spacing: 14) {
                spendOverTimeCard
                HStack(alignment: .top, spacing: 14) {
                    costBreakdownCard
                    resourceUtilizationCard
                }
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                spendOverTimeCard
                costBreakdownCard
                    .frame(width: 290)
                resourceUtilizationCard
                    .frame(width: 290)
            }
        }
    }

    private var spendOverTimeCard: some View {
        CTXGlassPanel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Spend Over Time", systemImage: "chart.xyaxis.line")
                        .font(.headline)
                    Spacer()
                    let avgDaily = report.timeSeries.isEmpty ? 0 : (report.summary.windowSpendUSD / max(1.0, Double(report.timeSeries.count)))
                    Text("Daily Avg: \(formatCurrency(avgDaily))")
                        .font(.caption2.weight(.semibold).monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }

                if report.timeSeries.isEmpty {
                    CTXEmptyStateView(title: "No Data", message: "No historical data points available.")
                        .frame(height: 190)
                } else {
                    Chart(report.timeSeries) { pt in
                        BarMark(
                            x: .value("Date", pt.label),
                            y: .value("Daily Spend", pt.totalCost),
                            width: .ratio(0.55)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(4)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.secondary.opacity(0.2))
                            AxisValueLabel {
                                if let doubleVal = value.as(Double.self) {
                                    Text("$\(Int(doubleVal))")
                                        .font(.caption2.monospaced())
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.caption2)
                        }
                    }
                    .frame(height: 190)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var costBreakdownCard: some View {
        CTXGlassPanel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Cost Breakdown", systemImage: "chart.pie.fill")
                    .font(.headline)

                let total = max(0.01, report.summary.windowSpendUSD)
                let cpuShare = report.summary.totalComputeCostUSD > 0 ? report.summary.totalComputeCostUSD : report.rows.reduce(0.0) { $0 + $1.breakdown.cpuCost }
                let memShare = report.summary.totalMemoryCostUSD > 0 ? report.summary.totalMemoryCostUSD : report.rows.reduce(0.0) { $0 + $1.breakdown.memoryCost }
                let storageShare = report.summary.totalStorageCostUSD > 0 ? report.summary.totalStorageCostUSD : report.rows.reduce(0.0) { $0 + $1.breakdown.storageCost }
                let idleShare = report.summary.totalIdleCostUSD > 0 ? report.summary.totalIdleCostUSD : report.rows.reduce(0.0) { $0 + $1.breakdown.idleCost }

                VStack(spacing: 8) {
                    costShareRow(title: "Compute (CPU)", amount: cpuShare, total: total, color: .blue)
                    costShareRow(title: "Memory (RAM)", amount: memShare, total: total, color: .purple)
                    costShareRow(title: "Storage (PVC)", amount: storageShare, total: total, color: .orange)
                    costShareRow(title: "Cluster Idle Share", amount: idleShare, total: total, color: .gray)
                }
                .padding(.top, 4)

                Spacer(minLength: 8)

                Divider()

                HStack {
                    Text("Total Window Allocation")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatCurrency(report.summary.windowSpendUSD))
                        .font(.caption.weight(.bold).monospaced())
                }
            }
            .frame(minHeight: 190)
        }
    }

    private func costShareRow(title: String, amount: Double, total: Double, color: Color) -> some View {
        let percent = Int(round((amount / total) * 100))
        return VStack(spacing: 3) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(formatCurrency(amount)) (\(percent)%)")
                    .font(.caption2.monospaced())
            }
            ProgressView(value: min(1.0, max(0.0, amount / total)))
                .tint(color)
                .scaleEffect(x: 1, y: 0.5, anchor: .center)
        }
    }

    private var resourceUtilizationCard: some View {
        CTXGlassPanel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Resource Demand", systemImage: "speedometer")
                    .font(.headline)

                let allocCores = max(0.1, report.summary.totalCoresAllocated)
                let usedCores = report.summary.totalCoresUsed
                let cpuPct = min(1.0, usedCores / allocCores)

                let allocMem = max(0.1, report.summary.totalMemoryGiBAllocated)
                let usedMem = report.summary.totalMemoryGiBUsed
                let memPct = min(1.0, usedMem / allocMem)

                VStack(spacing: 10) {
                    utilizationGaugeRow(
                        title: "CPU Active vs Requested",
                        allocatedLabel: "\(String(format: "%.1f", allocCores)) Cores",
                        usedLabel: "\(String(format: "%.1f", usedCores)) Cores",
                        percentage: cpuPct,
                        color: .blue
                    )

                    utilizationGaugeRow(
                        title: "Memory Active vs Requested",
                        allocatedLabel: "\(String(format: "%.1f", allocMem)) GiB",
                        usedLabel: "\(String(format: "%.1f", usedMem)) GiB",
                        percentage: memPct,
                        color: .purple
                    )

                    // Top Cost Drivers Mini-List
                    if !report.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Top Cost Drivers")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            ForEach(Array(report.rows.prefix(3))) { row in
                                HStack {
                                    Text(row.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(formatCurrency(row.breakdown.totalCost))
                                        .font(.system(size: 10, weight: .semibold).monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.top, 2)
            }
            .frame(minHeight: 190)
        }
    }

    private func utilizationGaugeRow(title: String, allocatedLabel: String, usedLabel: String, percentage: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percentage * 100))% utilized")
                    .font(.caption2.weight(.bold).monospaced())
                    .foregroundStyle(percentage < 0.35 ? .orange : .green)
            }
            ProgressView(value: percentage)
                .tint(color)
                .scaleEffect(x: 1, y: 0.5, anchor: .center)
            HStack {
                Text("Used: \(usedLabel)")
                    .font(.system(size: 9).monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Req: \(allocatedLabel)")
                    .font(.system(size: 9).monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Recommendations Section

    private var recommendationsColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 280, maximum: .infinity), spacing: 12)]
    }

    private var recommendationsSection: some View {
        CTXGlassPanel(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("FinOps Advisor Â· Optimization Opportunities", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Text("Save up to \(formatCurrency(report.summary.potentialMonthlySavingsUSD))/mo")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }

                LazyVGrid(columns: recommendationsColumns, spacing: 12) {
                    ForEach(report.recommendations.prefix(6)) { rec in
                        recommendationCard(rec)
                    }
                }
            }
        }
    }

    private func recommendationCard(_ rec: FinOpsRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Impact + Savings badge
            HStack {
                Text(rec.severity.badgeLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(severityColor(rec.severity))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(severityColor(rec.severity).opacity(0.14), in: Capsule())

                Spacer()

                Text("Save \(formatCurrency(rec.monthlySavingsUSD))/mo")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
            }

            // Workload title & namespace
            HStack(spacing: 6) {
                Text(rec.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .help(rec.title)

                if let ns = rec.namespace {
                    Text(ns)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }

            // Metric info (concise, no long sentences)
            Text(rec.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Current vs Suggested Strip
            HStack(spacing: 6) {
                Text(rec.currentAllocation)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(rec.suggestedAllocation)
                    .font(.system(size: 11, weight: .semibold).monospaced())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }

            Spacer(minLength: 2)

            // Distinct, professional CTA Button
            Button {
                selectedRecommendation = rec
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                    Text("Review Safe Patch")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.75)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(minHeight: 135, alignment: .topLeading)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.75)
        }
    }

    // MARK: - Allocation Table Section (Full Width & Responsive)

    private var tableContentWidth: CGFloat {
        max(availableWidth - 2, 880)
    }

    private func computedColumnWidth(for column: SortColumn) -> CGFloat {
        if let custom = customColumnWidths[column] {
            return custom
        }

        let baseWidths: [SortColumn: CGFloat] = [
            .name: 240,
            .cpu: 85,
            .memory: 85,
            .storage: 85,
            .idle: 90,
            .totalSpend: 105,
            .monthlyRun: 110,
            .efficiency: 120
        ]

        let baseSpacingAndPadding: CGFloat = (CGFloat(SortColumn.allCases.count - 1) * 8) + 28
        var usedWidth: CGFloat = baseSpacingAndPadding
        var unconstrainedColumns: [SortColumn] = []

        for col in SortColumn.allCases {
            if let custom = customColumnWidths[col] {
                usedWidth += custom
            } else {
                usedWidth += baseWidths[col] ?? 85
                unconstrainedColumns.append(col)
            }
        }

        let extra = tableContentWidth - usedWidth
        guard extra > 0, !unconstrainedColumns.isEmpty else {
            return baseWidths[column] ?? 85
        }

        let weights: [SortColumn: CGFloat] = [
            .name: 0.38,
            .cpu: 0.07,
            .memory: 0.07,
            .storage: 0.07,
            .idle: 0.08,
            .totalSpend: 0.11,
            .monthlyRun: 0.11,
            .efficiency: 0.11
        ]

        let totalUnconstrainedWeight = unconstrainedColumns.reduce(0) { $0 + (weights[$1] ?? 0.1) }
        guard totalUnconstrainedWeight > 0 else { return baseWidths[column] ?? 85 }

        let normalizedWeight = (weights[column] ?? 0.1) / totalUnconstrainedWeight
        return (baseWidths[column] ?? 85) + (extra * normalizedWeight)
    }

    private var allocationTableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Cost Allocation Matrix (\(viewModel.finopsAggregation.displayName))", systemImage: "tablecells")
                    .font(.headline)

                Text("\(sortedAndFilteredRows.count) items")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())

                Spacer()

                // Consolidated Filter Menu in Section Toolbar (never crammed inside column headers)
                finopsToolbarFilterMenu

                if finopsKindFilter != "All" || finopsMinSpendFilter > 0 || finopsEfficiencyFilter != "All" {
                    Button {
                        finopsKindFilter = "All"
                        finopsMinSpendFilter = 0
                        finopsEfficiencyFilter = "All"
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Reset")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            if finopsKindFilter != "All" || finopsMinSpendFilter > 0 || finopsEfficiencyFilter != "All" {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    Text("Active Filters:")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    if finopsKindFilter != "All" {
                        filterChip(title: "Kind: \(finopsKindFilter)") { finopsKindFilter = "All" }
                    }
                    if finopsMinSpendFilter > 0 {
                        filterChip(title: "Min Spend: $\(Int(finopsMinSpendFilter))") { finopsMinSpendFilter = 0 }
                    }
                    if finopsEfficiencyFilter != "All" {
                        filterChip(title: "Efficiency: \(finopsEfficiencyFilter)") { finopsEfficiencyFilter = "All" }
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }

            CTXGlassPanel(padding: 0) {
                if sortedAndFilteredRows.isEmpty {
                    CTXEmptyStateView(
                        title: "No Allocations Found",
                        message: "No resource data matching current search and filters."
                    )
                    .padding(32)
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            tableHeader
                            Divider()
                            ForEach(sortedAndFilteredRows) { row in
                                tableRow(row)
                                Divider().opacity(0.4)
                            }
                        }
                        .frame(width: tableContentWidth, alignment: .leading)
                    }
                }
            }
        }
    }

    private func filterChip(title: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    private var finopsToolbarFilterMenu: some View {
        let hasActiveFilters = finopsKindFilter != "All" || finopsMinSpendFilter > 0 || finopsEfficiencyFilter != "All"
        let kinds = Set(report.rows.compactMap(\.resourceKind)).sorted()

        return Menu {
            Menu("Resource Kind") {
                Button("All Kinds") { finopsKindFilter = "All" }
                Divider()
                ForEach(kinds, id: \.self) { k in
                    Button(k) { finopsKindFilter = k }
                }
            }
            Menu("Minimum Spend") {
                Button("Any Spend") { finopsMinSpendFilter = 0 }
                Divider()
                Button("> ") { finopsMinSpendFilter = 10 }
                Button("> ") { finopsMinSpendFilter = 50 }
                Button("> ") { finopsMinSpendFilter = 100 }
                Button("> ") { finopsMinSpendFilter = 500 }
            }
            Menu("Efficiency Score") {
                Button("All Scores") { finopsEfficiencyFilter = "All" }
                Divider()
                Button("Low (< 50%)") { finopsEfficiencyFilter = "Low" }
                Button("Optimal (> 80%)") { finopsEfficiencyFilter = "Optimal" }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                Text("Filter")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(hasActiveFilters ? Color.accentColor : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(hasActiveFilters ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            headerCell(title: "NAME", column: .name, alignment: .leading)
            headerCell(title: "CPU", column: .cpu, alignment: .trailing)
            headerCell(title: "MEMORY", column: .memory, alignment: .trailing)
            headerCell(title: "STORAGE", column: .storage, alignment: .trailing)
            headerCell(title: "IDLE SHARE", column: .idle, alignment: .trailing)
            headerCell(title: "TOTAL SPEND", column: .totalSpend, alignment: .trailing)
            headerCell(title: "MONTHLY RUN", column: .monthlyRun, alignment: .trailing)
            headerCell(title: "EFFICIENCY", column: .efficiency, alignment: .trailing)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: tableContentWidth, alignment: .leading)
        .background(Color.primary.opacity(0.03))
    }

    private func headerCell(title: String, column: SortColumn, alignment: Alignment) -> some View {
        let width = computedColumnWidth(for: column)
        let isSorted = sortColumn == column

        return HStack(spacing: 0) {
            Button {
                if sortColumn == column {
                    sortAscending.toggle()
                } else {
                    sortColumn = column
                    sortAscending = column == .name
                }
            } label: {
                HStack(spacing: 4) {
                    if alignment == .trailing { Spacer(minLength: 0) }

                    Text(title)
                        .font(.caption2.weight(isSorted ? .bold : .semibold))
                        .foregroundStyle(isSorted ? Color.accentColor : .secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if isSorted {
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Color.accentColor)
                    }

                    if alignment == .leading { Spacer(minLength: 0) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to sort by \(title)")
            .frame(width: max(45, width - 8))

            CTXColumnResizeDivider(
                onDelta: { delta in
                    let cur = customColumnWidths[column] ?? width
                    customColumnWidths[column] = max(55, cur + delta)
                },
                onReset: {
                    customColumnWidths.removeValue(forKey: column)
                }
            )
            .frame(width: 8)
        }
        .frame(width: width)
    }

    private func tableRow(_ row: FinOpsAllocationRow) -> some View {
        Button {
            selectedRowDetail = row
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: iconForKind(row.resourceKind))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let ns = row.namespace, ns != row.name {
                            Text(ns)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(width: computedColumnWidth(for: .name), alignment: .leading)

                Text(formatCurrency(row.breakdown.cpuCost))
                    .font(.caption.monospacedDigit())
                    .frame(width: computedColumnWidth(for: .cpu), alignment: .trailing)

                Text(formatCurrency(row.breakdown.memoryCost))
                    .font(.caption.monospacedDigit())
                    .frame(width: computedColumnWidth(for: .memory), alignment: .trailing)

                Text(formatCurrency(row.breakdown.storageCost))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(row.breakdown.storageCost > 0 ? .primary : .secondary)
                    .frame(width: computedColumnWidth(for: .storage), alignment: .trailing)

                Text(formatCurrency(row.breakdown.idleCost))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: computedColumnWidth(for: .idle), alignment: .trailing)

                Text(formatCurrency(row.breakdown.totalCost))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: computedColumnWidth(for: .totalSpend), alignment: .trailing)

                Text(formatCurrency(row.monthlyRunRateUSD))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: computedColumnWidth(for: .monthlyRun), alignment: .trailing)

                HStack(spacing: 6) {
                    ProgressView(value: row.efficiencyScore)
                        .tint(efficiencyColor(row.efficiencyScore))
                        .scaleEffect(x: 1, y: 0.5, anchor: .center)

                    Text("\(Int(round(row.efficiencyScore * 100)))%")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(efficiencyColor(row.efficiencyScore))
                        .frame(width: 34, alignment: .trailing)
                }
                .frame(width: computedColumnWidth(for: .efficiency), alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(width: tableContentWidth, alignment: .leading)
            .contentShape(Rectangle())
            .background(selectedRowDetail?.id == row.id ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }


    // MARK: - Row Detail Sheet

    private func rowDetailSheet(_ row: FinOpsAllocationRow) -> some View {
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
                    selectedRowDetail = nil
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            HStack(spacing: 16) {
                detailStatBox(title: "TOTAL WINDOW SPEND", value: formatCurrency(row.breakdown.totalCost), tint: .primary)
                detailStatBox(title: "MONTHLY RUN RATE", value: formatCurrency(row.monthlyRunRateUSD), tint: .blue)
                detailStatBox(title: "EFFICIENCY SCORE", value: "\(Int(round(row.efficiencyScore * 100)))%", tint: efficiencyColor(row.efficiencyScore))
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

            // Matching recommendation if any
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
                            Text("Save \(formatCurrency(rec.monthlySavingsUSD))/mo")
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

    // MARK: - Recommendation Detail Sheet (Safe Verification & Patch Review)

    private func recommendationDetailSheet(_ rec: FinOpsRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(rec.title)
                            .font(.title3.weight(.bold))

                        Text(rec.riskLevel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                    Text(rec.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    selectedRecommendation = nil
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            // Financial Summary Strip
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT REQUEST")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(rec.currentAllocation)
                        .font(.callout.weight(.medium))
                }

                Divider().frame(height: 35)

                VStack(alignment: .leading, spacing: 4) {
                    Text("RECOMMENDED TARGET")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(rec.suggestedAllocation)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.green)
                }

                Divider().frame(height: 35)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ESTIMATED MONTHLY SAVINGS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(formatCurrency(rec.monthlySavingsUSD)) / month")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            // Safety Guardrail Callout
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safety Guardrails Applied")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(rec.safetyHeadroom) Â· Request is adjusted to fit actual consumption while container limits remain intact to eliminate CPU throttling and OOMKills.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            // Step 1: Verification Command
            if let verifyCmd = rec.verificationCommand {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Verify Live Pod Consumption in Terminal")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(verifyCmd)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(verifyCmd, forType: .string)
                            copiedVerifyCommand = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedVerifyCommand = false
                            }
                        } label: {
                            Label(copiedVerifyCommand ? "Copied!" : "Copy", systemImage: copiedVerifyCommand ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Step 2: YAML Patch Snippet
            if let yaml = rec.yamlPatchSnippet {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("2. Suggested Resource Patch (YAML)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(yaml, forType: .string)
                            copiedYAML = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedYAML = false
                            }
                        } label: {
                            Label(copiedYAML ? "Copied!" : "Copy YAML", systemImage: copiedYAML ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                        }
                    }

                    Text(yaml)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 600, height: 500)
    }

    // MARK: - Methodology & Safety Sheet

    private var methodologyAndSafetySheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkerboard")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FinOps Methodology & Safety Guardrails")
                            .font(.title3.weight(.bold))
                        Text("How costs are calculated, why right-sizing works, and how workloads are safeguarded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Done") {
                    showingMethodologyModal = false
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Question 1: How is the price determined?
                    methodologySection(
                        icon: "dollarsign.circle.fill",
                        color: .blue,
                        title: "1. How Pricing is Calculated",
                        description: "Kubernetes nodes are billed by your cloud provider (e.g. AWS, GCP, Azure). Pods share those nodes. CTX calculates cost allocations according to the FinOps Foundation and OpenCost specification:",
                        bullets: [
                            "vCPU Cost = Requested Cores Ã Hourly Rate ($0.0316/hr baseline on AWS m6i).",
                            "RAM Cost = Requested Memory GiB Ã Hourly Rate ($0.0042/hr baseline).",
                            "Persistent Storage = Bound PVC provisioned GiB Ã Monthly Rate ($0.08/GB EBS gp3).",
                            "Cluster Idle Reserve = Node capacity not requested by any pod, distributed proportionally across active workloads."
                        ]
                    )

                    // Question 2: How do you know savings are real?
                    methodologySection(
                        icon: "arrow.down.right.and.arrow.up.left",
                        color: .green,
                        title: "2. Why Right-Sizing Saves Real Cloud Money",
                        description: "In cloud clusters (EKS, GKE, AKS with Cluster Autoscaler or Karpenter), nodes scale based on *Requested* resources, NOT actual used CPU.",
                        bullets: [
                            "If your pods request 100 cores but only use 15 cores, your cloud provider forces 25 nodes to stay online.",
                            "When you right-size container requests to match actual demand, the autoscaler automatically consolidates pods onto fewer nodes and terminates unneeded instances.",
                            "This directly slashes your monthly cloud invoice without touching application code."
                        ]
                    )

                    // Question 3: How do you know you won't break anything?
                    methodologySection(
                        icon: "lock.shield.fill",
                        color: .orange,
                        title: "3. Safety Guardrails Against Outages & OOMKills",
                        description: "CTX is engineered to prevent outages, CPU throttling, or OOM (Out Of Memory) crashes:",
                        bullets: [
                            "+35% Headroom Buffer: We never set requests to bare minimums. Every recommendation includes a 35% safety headroom above peak consumption.",
                            "Limits Retained (Uncapped Bursts): We only adjust scheduling requests. Container limits are preserved at 2Ã headroom so unexpected traffic spikes are never throttled.",
                            "Terminal Verification: We provide the exact 'kubectl top pod' command so you can cross-check live metrics in your own terminal before making changes.",
                            "Dry-Run Safe: Always test patches with 'kubectl apply --dry-run=server' before deploying."
                        ]
                    )
                }
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .padding(22)
        .frame(width: 620, height: 520)
    }

    private func methodologySection(icon: String, color: Color, title: String, description: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }

            Text(description)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Text("â¢")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(color)
                        Text(bullet)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - OpenCost Popover

    private var openCostPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("How Costs are Calculated")
                    .font(.headline)
            }

            Text("CTX provides automatic, zero-setup FinOps estimation using on-demand cloud pricing profiles for CPU, memory, and storage.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("Connect OpenCost / Kubecost")
                .font(.subheadline.weight(.semibold))

            Text("If your cluster has OpenCost or Kubecost installed, CTX automatically proxies live telemetry. To install the lightweight OpenCost exporter, run:")
                .font(.caption2)
                .foregroundStyle(.secondary)

            let helmCmd = "helm upgrade --install opencost opencost-charts/opencost --namespace opencost --create-namespace"
            HStack {
                Text(helmCmd)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(helmCmd, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
        .frame(width: 380)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private func efficiencyColor(_ score: Double) -> Color {
        if score >= 0.70 { return .green }
        if score >= 0.45 { return .orange }
        return .red
    }

    private func efficiencySubtitle(_ score: Double) -> String {
        if score >= 0.70 { return "Optimal cluster utilization" }
        if score >= 0.45 { return "Moderate over-provisioning" }
        return "High unallocated waste"
    }

    private func severityColor(_ severity: FinOpsSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private func iconForKind(_ kind: String?) -> String {
        switch kind {
        case "Namespace", "Namespaces": return "square.stack.3d.up"
        case "Node", "Nodes": return "server.rack"
        case "Workload", "Workloads": return "shippingbox"
        default: return "circle.hexagongrid"
        }
    }
}
