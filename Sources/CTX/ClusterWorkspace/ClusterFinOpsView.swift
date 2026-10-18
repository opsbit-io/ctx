import SwiftUI
import Charts
import CTXCore

struct ClusterFinOpsView: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel
    @State private var showingMethodologyModal = false
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
    @State private var showingCustomDateRangePicker = false
    @State private var tempStartDate: Date = Date()
    @State private var tempEndDate: Date = Date()

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
            if finopsEfficiencyFilter == "Low" {
                if !row.hasLiveUsage || row.efficiencyScore >= 0.5 { return false }
            } else if finopsEfficiencyFilter == "Optimal" {
                if !row.hasLiveUsage || row.efficiencyScore < 0.8 { return false }
            }
            return true
        }

        return base.sorted { a, b in
            let order: ComparisonResult
            switch sortColumn {
            case .name:
                order = a.name.localizedCaseInsensitiveCompare(b.name)
            case .cpu:
                order = hasCostPricing ? compare(a.breakdown.cpuCost, b.breakdown.cpuCost) : compare(a.cpuCoresRequested, b.cpuCoresRequested)
            case .memory:
                order = hasCostPricing ? compare(a.breakdown.memoryCost, b.breakdown.memoryCost) : compare(a.memoryGiBRequested, b.memoryGiBRequested)
            case .storage:
                order = hasCostPricing ? compare(a.breakdown.storageCost, b.breakdown.storageCost) : compare(a.storageGiB, b.storageGiB)
            case .idle:
                order = hasCostPricing ? compare(a.breakdown.idleCost, b.breakdown.idleCost) : compare(a.cpuCoresUsed, b.cpuCoresUsed)
            case .totalSpend:
                order = hasCostPricing ? compare(a.breakdown.totalCost, b.breakdown.totalCost) : compare(a.cpuCoresRequested, b.cpuCoresRequested)
            case .monthlyRun:
                order = hasCostPricing ? compare(a.monthlyRunRateUSD, b.monthlyRunRateUSD) : compare(a.memoryGiBRequested, b.memoryGiBRequested)
            case .efficiency:
                order = compare(a.efficiencyScore, b.efficiencyScore)
            }
            if order == .orderedSame {
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return sortAscending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private func compare(_ lhs: Double, _ rhs: Double) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerBar
            if viewModel.isLoadingFinOpsProvider && viewModel.verifiedFinOpsReport == nil {
                finopsProviderBanner(
                    "Looking for OpenCost or Kubecost in the selected cluster…",
                    systemImage: "magnifyingglass",
                    tint: .blue
                )
            } else if !viewModel.finopsProviderMessage.isEmpty {
                finopsProviderBanner(
                    viewModel.finopsProviderMessage,
                    systemImage: "info.circle",
                    tint: .orange,
                    action: viewModel.isFinOpsProviderDetected ? .retry : .setup
                )
            }
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                if (viewModel.isFinOpsProviderDetected || viewModel.verifiedFinOpsReport != nil) && !viewModel.isLoadingFinOpsProvider {
                    viewModel.loadFinOpsCosts(bypassCache: true)
                }
            }
        }
        .sheet(item: $selectedRecommendation) { rec in
            ClusterFinOpsRecommendationSheet(
                rec: rec,
                formatCurrency: formatCurrency,
                onDismiss: { selectedRecommendation = nil }
            )
        }
        .sheet(item: $selectedRowDetail) { row in
            ClusterFinOpsRowDetailSheet(
                row: row,
                report: report,
                hasCostPricing: hasCostPricing,
                formatCurrency: formatCurrency,
                formatCores: formatCores,
                formatGiB: formatGiB,
                efficiencyColor: efficiencyColor,
                iconForKind: iconForKind,
                onDismiss: { selectedRowDetail = nil }
            )
        }
        .sheet(isPresented: $showingMethodologyModal) {
            ClusterFinOpsMethodologySheet(viewModel: viewModel, isPresented: $showingMethodologyModal)
        }
        .sheet(isPresented: $viewModel.isOpenCostSetupSheetPresented) {
            OpenCostSetupApprovalSheet(viewModel: viewModel)
        }
    }

    // MARK: - Header Bar (Unified, Seamless & Responsive)

    private var headerBar: some View {
        ViewThatFits(in: .horizontal) {
            // Single unified line (Standard / Wide Window - Zero wasted space)
            HStack(alignment: .center, spacing: 10) {
                titleAndAuthenticityBadge

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    aggregationDimensionMenu
                    timeWindowMenu
                    cloudPricingBadge
                    searchField
                }
            }

            // Compact two-line layout (Narrow Window - Controls grouped tightly)
            VStack(alignment: .leading, spacing: 10) {
                titleAndAuthenticityBadge

                HStack(spacing: 8) {
                    aggregationDimensionMenu
                    timeWindowMenu
                    cloudPricingBadge
                    Spacer()
                    searchField
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var titleAndAuthenticityBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.accentColor)

            Text("FinOps & Costs")
                .font(.system(size: 18, weight: .bold))

            dataAuthenticityBadge
        }
    }

    private var searchField: some View {
        CTXSearchField(placeholder: "Search allocation...", text: $viewModel.finopsSearchText)
            .frame(width: 175)
    }

    private var aggregationDimensionMenu: some View {
        Menu {
            ForEach(FinOpsAggregation.allCases) { agg in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.finopsAggregation = agg
                    }
                } label: {
                    HStack {
                        Label(agg.displayName, systemImage: iconForKind(agg.rawValue.capitalized))
                        if viewModel.finopsAggregation == agg {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconForKind(viewModel.finopsAggregation.rawValue.capitalized))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)

                Text(viewModel.finopsAggregation.displayName)
                    .font(.system(size: 11.5, weight: .semibold))

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("Group allocations by \(viewModel.finopsAggregation.displayName)")
    }

    private var timeWindowMenu: some View {
        Menu {
            Section {
                Button {
                    selectTimeWindow(.h24)
                } label: {
                    HStack {
                        Label("Last 24 Hours", systemImage: "clock")
                        if viewModel.finopsWindow == .h24 {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    selectTimeWindow(.d7)
                } label: {
                    HStack {
                        Label("Last 7 Days (Week)", systemImage: "calendar")
                        if viewModel.finopsWindow == .d7 {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    selectTimeWindow(.d30)
                } label: {
                    HStack {
                        Label("Last 30 Days (Month)", systemImage: "calendar")
                        if viewModel.finopsWindow == .d30 {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    selectTimeWindow(.monthToDate)
                } label: {
                    HStack {
                        Label("Month to Date", systemImage: "calendar.badge.clock")
                        if viewModel.finopsWindow == .monthToDate {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Section {
                Button {
                    tempStartDate = viewModel.finopsCustomStartDate
                    tempEndDate = viewModel.finopsCustomEndDate
                    showingCustomDateRangePicker = true
                } label: {
                    HStack {
                        Label("Custom Date Range...", systemImage: "calendar.badge.plus")
                        if viewModel.finopsWindow == .custom {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.finopsWindow == .custom ? "calendar.badge.clock" : "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)

                Text(timeWindowDisplayLabel)
                    .font(.system(size: 11.5, weight: .semibold))

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("Select analysis time window or custom date range")
        .popover(isPresented: $showingCustomDateRangePicker, arrowEdge: .bottom) {
            customDateRangePopover
        }
    }

    private func selectTimeWindow(_ window: FinOpsTimeWindow) {
        withAnimation(.easeInOut(duration: 0.15)) {
            viewModel.finopsWindow = window
            viewModel.cachedFinOpsReport = nil
            viewModel.lastFinOpsCacheKey = ""
        }
    }

    private var timeWindowDisplayLabel: String {
        switch viewModel.finopsWindow {
        case .h24: return "24 Hours"
        case .d7: return "7 Days"
        case .d30: return "30 Days"
        case .monthToDate: return "Month to Date"
        case .custom:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: viewModel.finopsCustomStartDate)
            let endStr = formatter.string(from: viewModel.finopsCustomEndDate)
            return "\(startStr) – \(endStr)"
        }
    }

    private var windowShortLabel: String {
        switch viewModel.finopsWindow {
        case .h24: return "24H"
        case .d7: return "7D"
        case .d30: return "30D"
        case .monthToDate: return "MTD"
        case .custom:
            let days = max(1, Calendar.current.dateComponents([.day], from: viewModel.finopsCustomStartDate, to: viewModel.finopsCustomEndDate).day ?? 1)
            return "\(days)D"
        }
    }

    // MARK: - Custom Date Range Popover (Compact, Clean & Professional)

    private var customDateRangePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.accentColor)

                Text("Custom Date Range")
                    .font(.system(size: 11.5, weight: .bold))

                Spacer()

                let diffDays = max(1, Calendar.current.dateComponents([.day], from: tempStartDate, to: tempEndDate).day ?? 1)
                Text("\(diffDays)d")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            Divider().opacity(0.4)

            // Date Pickers (Compact & Clean)
            VStack(spacing: 8) {
                HStack {
                    Text("From:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .leading)

                    DatePicker("", selection: $tempStartDate, in: ...tempEndDate, displayedComponents: [.date])
                        .datePickerStyle(.compact)
                        .labelsHidden()

                    Spacer()
                }

                HStack {
                    Text("To:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .leading)

                    DatePicker("", selection: $tempEndDate, in: tempStartDate...Date(), displayedComponents: [.date])
                        .datePickerStyle(.compact)
                        .labelsHidden()

                    Spacer()
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Actions
            HStack(spacing: 8) {
                Spacer()

                Button("Cancel") {
                    showingCustomDateRangePicker = false
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                Button {
                    viewModel.setCustomFinOpsDateRange(start: tempStartDate, end: tempEndDate)
                    showingCustomDateRangePicker = false
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Apply")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .frame(width: 230)
    }

    private var finopsCloudProvider: CloudProvider {
        switch viewModel.context.providerType {
        case .eks: .aws
        case .gke: .gcp
        case .aks: .azure
        case .local, .unknown: .kubernetes
        }
    }

    private var cloudPricingBadge: some View {
        HStack(spacing: 6) {
            ProviderIcon(provider: finopsCloudProvider, size: 13, fallbackTint: Color.accentColor)
            Text(report.dataSource.isLiveAgent ? report.dataSource.badgeTitle : (viewModel.finopsPricing.hasExplicitRates ? "Custom Rates" : "Pure Kubernetes"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.75)
        }
        .help(report.dataSource.isLiveAgent
            ? "Allocation values were reported by the detected in-cluster cost provider."
            : (viewModel.finopsPricing.hasExplicitRates
                ? "Estimated allocation using explicitly supplied rates. This is not cloud billing data."
                : "No verified pricing source is connected. CTX will not invent currency values."))
    }

    private var dataAuthenticityBadge: some View {

        Button {
            showingMethodologyModal = true
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(report.hasLivePodTelemetry ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(report.dataSource.isLiveAgent ? "Verified Cost Provider" : (report.hasLivePodTelemetry ? "Live Usage Snapshot" : "Requests Snapshot"))
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
        .help(report.dataSource.isLiveAgent
            ? "Costs and history came from OpenCost or Kubecost through the Kubernetes service proxy."
            : (report.hasLivePodTelemetry ? "Usage came from the current metrics snapshot." : "Allocation inputs came from declared Kubernetes requests; no usage history is implied."))
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
            if hasCostPricing {
                finopsKpiCard(
                    title: "ESTIMATED MONTHLY RUN RATE",
                    value: formatCurrency(report.summary.monthlyRunRateUSD),
                    subtitle: "Est. annualized \(formatCurrency(report.summary.monthlyRunRateUSD * 12))",
                    icon: "chart.line.uptrend.xyaxis",
                    tint: .blue
                )
                finopsKpiCard(
                    title: "MODELED WINDOW COST (\(windowShortLabel))",
                    value: formatCurrency(report.summary.windowSpendUSD),
                    subtitle: "Compute, memory, storage & idle",
                    icon: "creditcard.fill",
                    tint: .indigo
                )
                finopsKpiCard(
                    title: "RESOURCE EFFICIENCY",
                    value: hasComparableEfficiency ? "\(Int(round(report.summary.overallEfficiencyScore * 100)))%" : "Unavailable",
                    subtitle: hasComparableEfficiency ? efficiencySubtitle(report.summary.overallEfficiencyScore) : "No comparable cost-weighted usage sample",
                    icon: "gauge.with.needle.fill",
                    tint: hasComparableEfficiency ? efficiencyColor(report.summary.overallEfficiencyScore) : .secondary
                )
                finopsKpiCard(
                    title: "ESTIMATED POTENTIAL SAVINGS",
                    value: formatCurrency(report.summary.potentialMonthlySavingsUSD) + " / mo",
                    subtitle: "\(report.recommendations.count) advisory candidates from current metrics",
                    icon: "sparkles",
                    tint: .green
                )
            } else {
                finopsKpiCard(
                    title: "ALLOCATED CPU CORES",
                    value: formatCores(report.summary.totalCoresAllocated),
                    subtitle: report.summary.totalCoresUsed > 0 ? "Active: \(formatCores(report.summary.totalCoresUsed)) used (\(Int(round((report.summary.totalCoresUsed / max(0.001, report.summary.totalCoresAllocated)) * 100)))%)" : "Total pod requested cores",
                    icon: "cpu",
                    tint: .blue
                )
                finopsKpiCard(
                    title: "ALLOCATED MEMORY",
                    value: formatGiB(report.summary.totalMemoryGiBAllocated),
                    subtitle: report.summary.totalMemoryGiBUsed > 0 ? "Active: \(formatGiB(report.summary.totalMemoryGiBUsed)) used (\(Int(round((report.summary.totalMemoryGiBUsed / max(0.001, report.summary.totalMemoryGiBAllocated)) * 100)))%)" : "Total pod requested RAM",
                    icon: "memorychip",
                    tint: .purple
                )
                finopsKpiCard(
                    title: "CLUSTER EFFICIENCY",
                    value: report.summary.overallEfficiencyScore > 0 ? "\(Int(round(report.summary.overallEfficiencyScore * 100)))%" : (hasComparableEfficiency ? "0%" : "Telemetry Pending"),
                    subtitle: report.summary.overallEfficiencyScore > 0 ? efficiencySubtitle(report.summary.overallEfficiencyScore) : "Ratio of active usage to requests",
                    icon: "gauge.with.needle.fill",
                    tint: report.summary.overallEfficiencyScore > 0 ? efficiencyColor(report.summary.overallEfficiencyScore) : .secondary
                )
                finopsKpiCard(
                    title: "BOUND STORAGE (PVC)",
                    value: formatGiB(report.summary.totalStorageGiBAllocated),
                    subtitle: "\(report.rows.filter { $0.storageGiB > 0 }.count) namespaces with PVC claims",
                    icon: "internaldrive",
                    tint: .orange
                )
            }
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
        if availableWidth < 620 {
            VStack(spacing: 14) {
                spendOverTimeCard
                costBreakdownCard
                resourceUtilizationCard
            }
        } else if availableWidth < 920 {
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
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                        Text(hasCostPricing ? "No Historical Data in Window" : "OpenCost Provider Not Installed")
                            .font(.subheadline.weight(.semibold))
                        Text(hasCostPricing ? "No historical records were returned for this time range." : "Connect OpenCost to track daily cloud spending, historical cost burn, and trend analysis.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                        if !hasCostPricing {
                            Button {
                                viewModel.openOpenCostSetupWorkflow()
                            } label: {
                                Label("Set up OpenCost…", systemImage: "plus.circle.fill")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(height: 250)
    }

    private var costBreakdownCard: some View {
        CTXGlassPanel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label(hasCostPricing ? "Cost Breakdown" : "Resource Allocation Split", systemImage: "chart.pie.fill")
                    .font(.headline)

                if hasCostPricing {
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
                } else {
                    let totalReqCores = max(0.001, report.summary.totalCoresAllocated)
                    let totalReqMem = max(0.001, report.summary.totalMemoryGiBAllocated)
                    let totalStorage = report.summary.totalStorageGiBAllocated

                    VStack(spacing: 10) {
                        resourceShareRow(title: "CPU Requests", value: formatCores(totalReqCores), subtitle: "\(report.rows.count) workloads", color: .blue)
                        resourceShareRow(title: "Memory Requests", value: formatGiB(totalReqMem), subtitle: "\(report.rows.count) workloads", color: .purple)
                        resourceShareRow(title: "Bound Storage (PVC)", value: formatGiB(totalStorage), subtitle: "\(report.rows.filter { $0.storageGiB > 0 }.count) claims", color: .orange)
                        if report.summary.totalCoresUsed > 0 || report.summary.totalMemoryGiBUsed > 0 {
                            resourceShareRow(title: "Active CPU Telemetry", value: formatCores(report.summary.totalCoresUsed), subtitle: "\(Int(round((report.summary.totalCoresUsed / totalReqCores) * 100)))% of requests", color: .green)
                        }
                    }
                    .padding(.top, 4)

                    Spacer(minLength: 8)

                    Divider()

                    HStack {
                        Text("Resource Tracking Mode")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Authentic Declared")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 250)
    }

    private func resourceShareRow(title: String, value: String, subtitle: String, color: Color) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
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

                    // Top Cost / Resource Drivers Mini-List
                    if !report.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(hasCostPricing ? "Top Cost Drivers" : "Top Allocated \(viewModel.finopsAggregation.displayName)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            ForEach(Array(report.rows.prefix(3))) { row in
                                HStack {
                                    Text(row.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                    Spacer()
                                    if hasCostPricing {
                                        Text(formatCurrency(row.breakdown.totalCost))
                                            .font(.system(size: 10, weight: .semibold).monospaced())
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\(formatCores(row.cpuCoresRequested)) · \(formatGiB(row.memoryGiBRequested))")
                                            .font(.system(size: 9, weight: .semibold).monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 250)
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
            if kinds.count > 1 {
                Menu("Resource Kind") {
                    Picker("Resource Kind", selection: $finopsKindFilter) {
                        Text("All Kinds").tag("All")
                        ForEach(kinds, id: \.self) { kind in
                            Text(kind).tag(kind)
                        }
                    }
                }
            }
            Menu("Minimum Spend") {
                Picker("Minimum Spend", selection: $finopsMinSpendFilter) {
                    Text("Any Spend").tag(0.0)
                    Text("At least $1").tag(1.0)
                    Text("At least $10").tag(10.0)
                    Text("At least $50").tag(50.0)
                    Text("At least $100").tag(100.0)
                }
            }
            Menu("Efficiency Score") {
                Picker("Efficiency Score", selection: $finopsEfficiencyFilter) {
                    Text("All Scores").tag("All")
                    Text("Low (< 50%)").tag("Low")
                    Text("Optimal (≥ 80%)").tag("Optimal")
                }
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
            headerCell(title: hasCostPricing ? "CPU" : "CPU REQ", column: .cpu, alignment: .trailing)
            headerCell(title: hasCostPricing ? "MEMORY" : "MEM REQ", column: .memory, alignment: .trailing)
            headerCell(title: "STORAGE", column: .storage, alignment: .trailing)
            headerCell(title: hasCostPricing ? "IDLE SHARE" : "CPU USED", column: .idle, alignment: .trailing)
            headerCell(title: hasCostPricing ? "TOTAL SPEND" : "MEM USED", column: .totalSpend, alignment: .trailing)
            headerCell(title: hasCostPricing ? "MONTHLY RUN" : "STATUS", column: .monthlyRun, alignment: .trailing)
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

                if hasCostPricing {
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
                } else {
                    Text(formatCores(row.cpuCoresRequested))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(row.cpuCoresRequested > 0 ? .primary : .secondary)
                        .frame(width: computedColumnWidth(for: .cpu), alignment: .trailing)

                    Text(formatGiB(row.memoryGiBRequested))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(row.memoryGiBRequested > 0 ? .primary : .secondary)
                        .frame(width: computedColumnWidth(for: .memory), alignment: .trailing)

                    Text(row.storageGiB > 0 ? formatGiB(row.storageGiB) : "-")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(row.storageGiB > 0 ? .primary : .secondary)
                        .frame(width: computedColumnWidth(for: .storage), alignment: .trailing)

                    Text(row.hasLiveUsage && row.cpuCoresUsed > 0 ? formatCores(row.cpuCoresUsed) : "-")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(row.cpuCoresUsed > 0 ? .primary : .secondary)
                        .frame(width: computedColumnWidth(for: .idle), alignment: .trailing)

                    Text(row.hasLiveUsage && row.memoryGiBUsed > 0 ? formatGiB(row.memoryGiBUsed) : "-")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(row.memoryGiBUsed > 0 ? .primary : .secondary)
                        .frame(width: computedColumnWidth(for: .totalSpend), alignment: .trailing)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(row.hasLiveUsage ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(row.hasLiveUsage ? "Live" : "Declared")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(row.hasLiveUsage ? .primary : .secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(row.hasLiveUsage ? Color.green.opacity(0.1) : Color.secondary.opacity(0.08), in: Capsule())
                    .frame(width: computedColumnWidth(for: .monthlyRun), alignment: .trailing)
                }

                Group {
                    if row.hasLiveUsage {
                        HStack(spacing: 6) {
                            ProgressView(value: row.efficiencyScore)
                                .tint(efficiencyColor(row.efficiencyScore))
                                .scaleEffect(x: 1, y: 0.5, anchor: .center)

                            Text("\(Int(round(row.efficiencyScore * 100)))%")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(efficiencyColor(row.efficiencyScore))
                                .frame(width: 34, alignment: .trailing)
                        }
                    } else {
                        Text("Unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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


    // MARK: - Helpers

    var hasCostPricing: Bool {
        report.dataSource.isLiveAgent || viewModel.finopsPricing.hasExplicitRates
    }

    func formatCores(_ cores: Double) -> String {
        if cores <= 0 { return "0 Cores" }
        if cores < 1.0 {
            return "\(Int(round(cores * 1000)))m"
        }
        return String(format: "%.2f Cores", cores)
    }

    func formatGiB(_ gib: Double) -> String {
        if gib <= 0 { return "0 GiB" }
        if gib < 1.0 {
            return "\(Int(round(gib * 1024))) MiB"
        }
        return String(format: "%.1f GiB", gib)
    }

    func formatCurrency(_ value: Double) -> String {
        guard report.dataSource.isLiveAgent || viewModel.finopsPricing.hasExplicitRates else { return "Unavailable" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private var hasComparableEfficiency: Bool {
        report.rows.contains(where: \.hasLiveUsage)
    }

    private enum ProviderBannerAction {
        case none
        case setup
        case retry
    }

    private func finopsProviderBanner(
        _ message: String,
        systemImage: String,
        tint: Color,
        action: ProviderBannerAction = .none
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
            if action == .setup {
                Button {
                    viewModel.openOpenCostSetupWorkflow()
                } label: {
                    Label("Set up OpenCost…", systemImage: "shield.lefthalf.filled.badge.checkmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(.small)
            } else if action == .retry {
                Button {
                    viewModel.loadFinOpsCosts(bypassCache: true)
                } label: {
                    Label("Retry Connection", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 0.75)
        }
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
