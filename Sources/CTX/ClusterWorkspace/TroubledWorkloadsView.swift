import CTXCore
import SwiftUI

/// Authentic Apple-grade Diagnostics & Issues Triage Center (`TroubledWorkloadsView`).
///
/// Designed around a responsive Master-Detail Split Architecture (identical in ergonomics to `ClusterGitOpsView`):
/// - Single-row unified header (`CTXUnifiedHeaderBar`) with sidebar toggle, grouping mode (`By Rule / By Workload`), and search.
/// - Interactive 4-card KPI strip (`CTXInteractiveKpiCard`) for 1-click category filtering.
/// - Left Master Sidebar: Scannable list of diagnostic rules (or workloads) sorted by severity and impact count.
/// - Right Detail Inspector: Explains the selected rule, provides an actionable Remediation Guide ("How to Fix"),
///   and lists affected Kubernetes resources with 1-click `Inspect` and `Logs` actions.
struct TroubledWorkloadsView: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel

    enum IssueCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case runtime = "Runtime"
        case configuration = "Configuration"
        case security = "Security"
        case reliability = "Reliability"

        var id: String { rawValue }
    }

    enum GroupingMode: String, CaseIterable, Identifiable {
        case byRule = "By Rule"
        case byWorkload = "By Workload"
        var id: String { rawValue }
    }

    @State private var filterText: String = ""
    @State private var selectedCategory: IssueCategory = .all
    @State private var groupingMode: GroupingMode = .byRule
    @State private var selectedRuleID: String?
    @State private var selectedWorkloadID: String?
    @State private var isSidebarCollapsed: Bool = false
    @State private var affectedResourceFilter: String = ""

    private var scopedIssues: [ResourceDiagnosticIssue] {
        let all = viewModel.diagnosticReport.allIssues
        switch viewModel.selectedNamespace {
        case .allNamespaces:
            return all
        case .defaultNamespace:
            return all.filter { $0.resourceNamespace == "default" || $0.resourceNamespace == nil }
        case .namespace(let ns):
            return all.filter { $0.resourceNamespace == ns || $0.resourceNamespace == nil }
        }
    }

    private var categoryFilteredIssues: [ResourceDiagnosticIssue] {
        switch selectedCategory {
        case .all:
            return scopedIssues
        case .runtime:
            return scopedIssues.filter { $0.category == DiagnosticCategory.runtime }
        case .configuration:
            return scopedIssues.filter { $0.category == DiagnosticCategory.configuration || $0.category == DiagnosticCategory.runtime }
        case .security:
            return scopedIssues.filter { $0.category == DiagnosticCategory.security }
        case .reliability:
            return scopedIssues.filter { $0.category == DiagnosticCategory.reliability }
        }
    }

    private var filteredIssues: [ResourceDiagnosticIssue] {
        guard !filterText.isEmpty else { return categoryFilteredIssues }
        return categoryFilteredIssues.filter { issue in
            issue.resourceName.localizedCaseInsensitiveContains(filterText)
                || issue.title.localizedCaseInsensitiveContains(filterText)
                || issue.message.localizedCaseInsensitiveContains(filterText)
                || issue.ruleId.localizedCaseInsensitiveContains(filterText)
                || (issue.resourceNamespace ?? "").localizedCaseInsensitiveContains(filterText)
        }
    }

    private var criticalAndRuntimeCount: Int {
        scopedIssues.filter { $0.severity == DiagnosticSeverity.error || $0.category == DiagnosticCategory.runtime }.count
    }

    private var configCount: Int {
        scopedIssues.filter { $0.category == DiagnosticCategory.configuration || $0.category == DiagnosticCategory.runtime }.count
    }

    private var securityCount: Int {
        scopedIssues.filter { $0.category == DiagnosticCategory.security }.count
    }

    private var reliabilityCount: Int {
        scopedIssues.filter { $0.category == DiagnosticCategory.reliability }.count
    }

    private var isRefreshingDiagnostics: Bool {
        ClusterWorkspaceViewModel.diagnosticResourceKinds.contains { kind in
            if let s = ClusterWorkspaceSection.section(for: kind) {
                return viewModel.isLoading(section: s)
            }
            return false
        }
    }

    private var isAnalyzing: Bool {
        isRefreshingDiagnostics && viewModel.diagnosticReport.allIssues.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar

            if isAnalyzing {
                CTXGlassPanel {
                    CTXLoadingStateView(
                        title: "Analyzing Cluster Diagnostics",
                        message: "Evaluating workloads, pods, security contexts, and configuration references...",
                        centered: true
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scopedIssues.isEmpty {
                CTXGlassPanel {
                    CTXEmptyStateView(
                        title: "All Clear",
                        message: "No runtime, configuration, security, or reliability issues detected in '\(viewModel.namespace)'.",
                        systemImage: "checkmark.shield.fill"
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                kpiStrip

                if filteredIssues.isEmpty {
                    CTXGlassPanel {
                        VStack(spacing: 10) {
                            CTXEmptyStateView(
                                title: "No Matching Findings",
                                message: filterText.isEmpty ? "No issues in this category." : "No findings match '\(filterText)'."
                            )
                            Button("Reset Filters") {
                                selectedCategory = .all
                                filterText = ""
                            }
                            .buttonStyle(CTXSecondaryButton())
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    masterDetailContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            reloadAllDiagnosticSources(bypassCache: false)
        }
        .onAppear {
            syncSelection()
        }
        .onChange(of: ruleGroups.map(\.id)) { _, _ in
            syncSelection()
        }
        .onChange(of: workloadGroups.map(\.id)) { _, _ in
            syncSelection()
        }
    }

    private func syncSelection() {
        if selectedRuleID == nil || !ruleGroups.contains(where: { $0.id == selectedRuleID }) {
            selectedRuleID = ruleGroups.first?.id
        }
        if selectedWorkloadID == nil || !workloadGroups.contains(where: { $0.id == selectedWorkloadID }) {
            selectedWorkloadID = workloadGroups.first?.id
        }
    }

    // MARK: - Unified Single-Row Header

    private var headerBar: some View {
        CTXUnifiedHeaderBar(
            title: "Diagnostics & Issues",
            systemImage: "exclamationmark.triangle.fill",
            iconTint: criticalAndRuntimeCount > 0 ? .red : .orange,
            countBadge: filteredIssues.count,
            countTint: criticalAndRuntimeCount > 0 ? .red : .orange,
            isSidebarCollapsed: $isSidebarCollapsed,
            sidebarHelp: isSidebarCollapsed ? "Show Triage List" : "Hide Triage List"
        ) {
            if criticalAndRuntimeCount > 0 {
                CTXSemanticPill(
                    text: "\(criticalAndRuntimeCount) Critical / Runtime",
                    systemImage: "bolt.trianglebadge.exclamationmark.fill",
                    tint: .red
                )
            }
        } trailingControls: {
            Picker("Group", selection: $groupingMode) {
                ForEach(GroupingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 175)

            CTXSearchField(placeholder: "Filter rule, resource, message...", text: $filterText)
                .frame(minWidth: 160, idealWidth: 230, maxWidth: 270)
        }
    }

    // MARK: - Interactive 4-Card KPI Strip

    private var kpiStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                kpiCards
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                kpiCards
            }
        }
    }

    @ViewBuilder
    private var kpiCards: some View {
        CTXInteractiveKpiCard(
            title: "All Findings",
            value: "\(scopedIssues.count)",
            subtitle: "\(ruleGroupsAll.count) distinct rules",
            systemImage: "stethoscope",
            tint: .red,
            isSelected: selectedCategory == .all
        ) {
            withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = .all }
        }

        CTXInteractiveKpiCard(
            title: "Runtime & Config",
            value: "\(configCount)",
            subtitle: "Crashes & broken refs",
            systemImage: "gearshape.2.fill",
            tint: .orange,
            isSelected: selectedCategory == .configuration
        ) {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = selectedCategory == .configuration ? .all : .configuration
            }
        }

        CTXInteractiveKpiCard(
            title: "Security Risks",
            value: "\(securityCount)",
            subtitle: "Privilege & root access",
            systemImage: "lock.shield.fill",
            tint: .purple,
            isSelected: selectedCategory == .security
        ) {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = selectedCategory == .security ? .all : .security
            }
        }

        CTXInteractiveKpiCard(
            title: "Reliability",
            value: "\(reliabilityCount)",
            subtitle: "Limits & probes",
            systemImage: "gauge.with.needle.fill",
            tint: .blue,
            isSelected: selectedCategory == .reliability
        ) {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = selectedCategory == .reliability ? .all : .reliability
            }
        }
    }

    // MARK: - Master-Detail Split Content

    private var masterDetailContent: some View {
        GeometryReader { geo in
            let showSidebar = !isSidebarCollapsed && geo.size.width >= 760
            let sidebarWidth = min(max(geo.size.width * 0.34, 280), 400)

            HStack(alignment: .top, spacing: 12) {
                if showSidebar {
                    masterSidebar
                        .frame(width: sidebarWidth)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Left Master Sidebar

    private var masterSidebar: some View {
        CTXGlassPanel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(groupingMode == .byRule ? "DIAGNOSTIC RULES (\(ruleGroups.count))" : "AFFECTED WORKLOADS (\(workloadGroups.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().opacity(0.5)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 6) {
                        switch groupingMode {
                        case .byRule:
                            ForEach(ruleGroups) { group in
                                ruleMasterRow(group)
                            }
                        case .byWorkload:
                            ForEach(workloadGroups) { group in
                                workloadMasterRow(group)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func ruleMasterRow(_ group: RuleGroup) -> some View {
        let isSelected = group.id == selectedRuleID
        let tint = group.severity.tint

        return Button {
            selectedRuleID = group.id
            affectedResourceFilter = ""
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: group.severity.systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(group.ruleId)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        DiagnosticCategoryBadge(category: group.category)
                    }
                }

                Spacer(minLength: 4)

                Text("\(group.issues.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7.5)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.16), in: Capsule())
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.025))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.05), lineWidth: isSelected ? 1.2 : 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func workloadMasterRow(_ group: WorkloadGroup) -> some View {
        let isSelected = group.id == selectedWorkloadID
        let tint = group.highestSeverity.tint

        return Button {
            selectedWorkloadID = group.id
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: group.highestSeverity.systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name)
                        .font(.system(size: 12, weight: isSelected ? .bold : .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(group.kind.title.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                        if let ns = group.namespace, ns != "-" {
                            Text(ns)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 4)

                Text("\(group.issues.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7.5)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.16), in: Capsule())
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.025))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.05), lineWidth: isSelected ? 1.2 : 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Detail Inspector

    @ViewBuilder
    private var detailPane: some View {
        switch groupingMode {
        case .byRule:
            if let group = ruleGroups.first(where: { $0.id == selectedRuleID }) ?? ruleGroups.first {
                ruleDetailInspector(group)
            } else {
                CTXGlassPanel {
                    CTXEmptyStateView(title: "Select a Rule", message: "Choose a diagnostic rule on the left to inspect affected resources.")
                }
            }
        case .byWorkload:
            if let group = workloadGroups.first(where: { $0.id == selectedWorkloadID }) ?? workloadGroups.first {
                workloadDetailInspector(group)
            } else {
                CTXGlassPanel {
                    CTXEmptyStateView(title: "Select a Workload", message: "Choose an affected workload on the left to inspect its findings.")
                }
            }
        }
    }

    private func ruleDetailInspector(_ group: RuleGroup) -> some View {
        let tint = group.severity.tint
        let visibleIssues = group.issues.filter { issue in
            guard !affectedResourceFilter.isEmpty else { return true }
            let q = affectedResourceFilter.lowercased()
            return issue.resourceName.lowercased().contains(q)
                || (issue.resourceNamespace ?? "").lowercased().contains(q)
                || issue.message.lowercased().contains(q)
        }

        return CTXGlassPanel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Top Rule Header & Remediation Box
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: group.severity.systemImage)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 38, height: 38)
                            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(group.title)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.primary)

                                Text(group.ruleId)
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06), in: Capsule())

                                DiagnosticCategoryBadge(category: group.category)
                            }

                            HStack(spacing: 8) {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.cyan)
                                Text("Remediation: \(group.recommendation)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        CTXSemanticPill(
                            text: "\(group.issues.count) Affected Resource\(group.issues.count == 1 ? "" : "s")",
                            systemImage: "cube.box.fill",
                            tint: tint
                        )
                    }

                    if group.issues.count > 5 {
                        HStack {
                            Text("AFFECTED RESOURCES (\(visibleIssues.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            Spacer()
                            CTXSearchField(placeholder: "Filter affected resources...", text: $affectedResourceFilter)
                                .frame(width: 220)
                        }
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.02))

                Divider().opacity(0.5)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(visibleIssues.enumerated()), id: \.offset) { _, issue in
                            affectedResourceRow(issue)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func workloadDetailInspector(_ group: WorkloadGroup) -> some View {
        let tint = group.highestSeverity.tint

        return CTXGlassPanel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: group.highestSeverity.systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(group.kind.title.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                            Text(group.name)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)

                            if let ns = group.namespace, ns != "-" {
                                Text(ns)
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.14), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("\(group.issues.count) diagnostic finding\(group.issues.count == 1 ? "" : "s") detected on this resource")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let first = group.issues.first {
                        inspectButton(for: first)
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.02))

                Divider().opacity(0.5)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(group.issues.enumerated()), id: \.offset) { _, issue in
                            CTXGlassPanel(padding: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Image(systemName: issue.severity.systemImage)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(issue.severity.tint)

                                        Text(issue.title)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.primary)

                                        Text(issue.ruleId)
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1.5)
                                            .background(Color.primary.opacity(0.06), in: Capsule())

                                        DiagnosticCategoryBadge(category: issue.category)

                                        Spacer()
                                    }

                                    Text(issue.message)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.primary)

                                    HStack(spacing: 6) {
                                        Image(systemName: "wrench.and.screwdriver.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.cyan)
                                        Text(issue.recommendation)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Data Models & Helpers

    private struct RuleGroup: Identifiable {
        let id: String // ruleId
        let ruleId: String
        let title: String
        let severity: DiagnosticSeverity
        let category: DiagnosticCategory
        let recommendation: String
        let issues: [ResourceDiagnosticIssue]
    }

    private var ruleGroupsAll: [RuleGroup] {
        buildRuleGroups(from: scopedIssues)
    }

    private var ruleGroups: [RuleGroup] {
        buildRuleGroups(from: filteredIssues)
    }

    private func buildRuleGroups(from list: [ResourceDiagnosticIssue]) -> [RuleGroup] {
        let grouped = Dictionary(grouping: list, by: \.ruleId)
        return grouped.compactMap { ruleId, items -> RuleGroup? in
            guard let first = items.first else { return nil }
            return RuleGroup(
                id: ruleId,
                ruleId: ruleId,
                title: first.title,
                severity: first.severity,
                category: first.category,
                recommendation: first.recommendation,
                issues: items
            )
        }
        .sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return lhs.issues.count > rhs.issues.count
        }
    }

    private func affectedResourceRow(_ issue: ResourceDiagnosticIssue) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(issue.resourceKind.title.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text(issue.resourceName)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let ns = issue.resourceNamespace, ns != "-" {
                        Text(ns)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                }

                Text(issue.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if issue.resourceKind == .pods {
                Button {
                    if let podRow = viewModel.resourceList(for: .pods)?.rows.first(where: {
                        $0.name == issue.resourceName && ($0.namespace ?? "") == (issue.resourceNamespace ?? "")
                    }) {
                        viewModel.selectLogPod(podRow)
                        viewModel.selectedSection = .logs
                    } else {
                        viewModel.selectedSection = .logs
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 9.5))
                        Text("Logs")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open Container Logs for \(issue.resourceName)")
            }

            inspectButton(for: issue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.75)
        }
    }

    private struct WorkloadGroup: Identifiable {
        let id: String
        let kind: KubernetesResourceKind
        let name: String
        let namespace: String?
        let highestSeverity: DiagnosticSeverity
        let issues: [ResourceDiagnosticIssue]
    }

    private var workloadGroups: [WorkloadGroup] {
        let grouped = Dictionary(grouping: filteredIssues) { issue in
            "\(issue.resourceKind.rawValue)/\(issue.resourceNamespace ?? "-")/\(issue.resourceName)"
        }
        return grouped.compactMap { key, items -> WorkloadGroup? in
            guard let first = items.first else { return nil }
            let highest = items.map(\.severity).max() ?? DiagnosticSeverity.info
            return WorkloadGroup(
                id: key,
                kind: first.resourceKind,
                name: first.resourceName,
                namespace: first.resourceNamespace,
                highestSeverity: highest,
                issues: items
            )
        }
        .sorted { lhs, rhs in
            if lhs.highestSeverity != rhs.highestSeverity {
                return lhs.highestSeverity > rhs.highestSeverity
            }
            return lhs.issues.count > rhs.issues.count
        }
    }

    private func inspectButton(for issue: ResourceDiagnosticIssue) -> some View {
        Button {
            Task {
                await viewModel.navigateToResource(
                    kind: issue.resourceKind,
                    name: issue.resourceName,
                    namespace: issue.resourceNamespace,
                    tab: .diagnostics
                )
            }
        } label: {
            HStack(spacing: 4) {
                Text("Inspect")
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Inspect \(issue.resourceName)")
    }

    private func reloadAllDiagnosticSources(bypassCache: Bool) {
        viewModel.loadResource(kind: .pods, bypassCache: bypassCache)
        viewModel.loadResource(kind: .nodes, bypassCache: bypassCache)
        viewModel.loadResource(kind: .workloads, bypassCache: bypassCache)
        viewModel.loadResource(kind: .services, bypassCache: bypassCache)
        viewModel.loadResource(kind: .ingress, bypassCache: bypassCache)
        viewModel.loadResource(kind: .configMaps, bypassCache: bypassCache)
        viewModel.loadResource(kind: .secretMetadata, bypassCache: bypassCache)
        viewModel.loadResource(kind: .pvc, bypassCache: bypassCache)
    }
}
