import AppKit
import CTXCore
import SwiftUI

/// Authentic Apple-grade GitOps & Progressive Delivery Center for CTX.
///
/// Unifies ArgoCD Applications, Flux CD Kustomizations/HelmReleases, and Flagger Canaries
/// in a zero-clutter, fully responsive macOS native experience:
/// - Single-row unified header (`CTXUnifiedHeaderBar`) with provider tabs, search, and reload.
/// - Interactive 4-card KPI strip (`CTXInteractiveKpiCard`) for 1-click Sync/Health filtering.
/// - Adaptive Master-Detail split (`GeometryReader` + collapsible list) with zero clipping.
/// - Rich application detail inspector showing Source & Revision flow, Flagger Canary progress,
///   Managed Kubernetes Resources with one-click navigation and live, read-only state.
struct ClusterGitOpsView: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case synced = "Synced"
        case outOfSync = "OutOfSync"
        case degraded = "Attention"
        var id: String { rawValue }
    }

    @State private var searchText = ""
    @State private var selectedProvider = "All"
    @State private var statusFilter: StatusFilter = .all
    @State private var isMasterListCollapsed = false
    @State private var resourceSearchText = ""

    private var scopedItems: [GitOpsApplicationItem] {
        let allItems = viewModel.gitOpsResult?.items ?? []
        guard case .namespace(let ns) = viewModel.selectedNamespace else {
            return allItems
        }
        return allItems.filter { item in
            let targetNS = (!item.destinationNamespace.isEmpty && item.destinationNamespace != KubernetesGitOpsService.unknownValue)
                ? item.destinationNamespace
                : item.namespace
            return targetNS == ns || item.namespace == ns
        }
    }

    private var availableProviders: [String] {
        var set = Set(scopedItems.map(\.provider))
        for installed in viewModel.gitOpsResult?.installedControllers ?? [] {
            set.insert(installed)
        }
        let ordered = ["ArgoCD", "Flux CD", "Flagger"].filter { set.contains($0) }
        return ["All"] + ordered
    }

    private var filteredItems: [GitOpsApplicationItem] {
        scopedItems.filter { item in
            if selectedProvider != "All" && item.provider != selectedProvider {
                return false
            }
            switch statusFilter {
            case .all:
                break
            case .synced:
                guard isSynced(item) && isHealthy(item) else { return false }
            case .outOfSync:
                guard isOutOfSync(item) else { return false }
            case .degraded:
                guard isDegradedOrAttention(item) else { return false }
            }
            if searchText.isEmpty { return true }
            let q = searchText.lowercased()
            return item.name.lowercased().contains(q)
                || item.namespace.lowercased().contains(q)
                || item.destinationNamespace.lowercased().contains(q)
                || item.repoURL.lowercased().contains(q)
                || item.chart.lowercased().contains(q)
                || item.path.lowercased().contains(q)
                || item.kind.lowercased().contains(q)
        }
    }

    private var syncedHealthyCount: Int {
        scopedItems.filter { isSynced($0) && isHealthy($0) }.count
    }

    private var outOfSyncCount: Int {
        scopedItems.filter { isOutOfSync($0) }.count
    }

    private var attentionCount: Int {
        scopedItems.filter { isDegradedOrAttention($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar
            if !scopedItems.isEmpty {
                kpiStrip
            }
            mainContentArea
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let notice = viewModel.gitOpsSourceNotice {
                    CTXFloatingToast(
                        text: notice,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .orange
                    )
                }
            }
            .padding(.top, 10)
        }
        .overlay(alignment: .bottom) {
            if let result = viewModel.gitOpsActionResult {
                CTXFloatingToast(
                    text: result.message,
                    systemImage: result.success ? "checkmark.circle.fill" : "exclamationmark.octagon.fill",
                    tint: result.success ? .green : .red,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            viewModel.gitOpsActionResult = nil
                        }
                    }
                )
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: viewModel.gitOpsActionResult != nil)
        .onAppear {
            if viewModel.gitOpsResult == nil {
                viewModel.loadGitOps()
            } else if viewModel.selectedGitOpsApp == nil {
                viewModel.selectedGitOpsApp = filteredItems.first
            }
        }
        .onChange(of: filteredItems) { _, newItems in
            if let current = viewModel.selectedGitOpsApp, !newItems.contains(where: { $0.id == current.id }) {
                viewModel.selectedGitOpsApp = newItems.first
            } else if viewModel.selectedGitOpsApp == nil {
                viewModel.selectedGitOpsApp = newItems.first
            }
        }
    }

    // MARK: - Unified Single-Row Responsive Header

    private var headerBar: some View {
        CTXUnifiedHeaderBar(
            title: "GitOps & Delivery",
            systemImage: "arrow.triangle.branch",
            iconTint: .indigo,
            countBadge: scopedItems.count,
            countTint: .indigo,
            isSidebarCollapsed: $isMasterListCollapsed,
            sidebarHelp: isMasterListCollapsed ? "Show Applications List" : "Hide Applications List"
        ) {
            HStack(spacing: 6) {

                ForEach(viewModel.gitOpsResult?.installedControllers ?? [], id: \.self) { controller in
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            selectedProvider = (selectedProvider == controller) ? "All" : controller
                        }
                    } label: {
                        HStack(spacing: 5) {
                            GitOpsBrandIconView(provider: controller, size: 13)
                            Text(controller)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(selectedProvider == controller ? providerTint(controller) : .primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            (selectedProvider == controller ? providerTint(controller) : Color.secondary)
                                .opacity(selectedProvider == controller ? 0.18 : 0.1),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    selectedProvider == controller ? providerTint(controller).opacity(0.55) : Color.clear,
                                    lineWidth: 0.8
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Filter by \(controller)")
                }
            }
        } trailingControls: {
            if availableProviders.count > 2 {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(availableProviders, id: \.self) { provider in
                        Text(provider).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            CTXSearchField(placeholder: "Filter apps, repos, charts...", text: $searchText)
                .frame(minWidth: 160, idealWidth: 220, maxWidth: 260)
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
            title: "Applications",
            value: "\(scopedItems.count)",
            subtitle: statusFilter == .all ? "Showing all" : "Click to show all",
            systemImage: "square.stack.3d.up.fill",
            tint: .indigo,
            isSelected: statusFilter == .all
        ) {
            withAnimation(.easeInOut(duration: 0.15)) { statusFilter = .all }
        }

        CTXInteractiveKpiCard(
            title: "Synced & Healthy",
            value: "\(syncedHealthyCount)",
            subtitle: "Matching desired state",
            systemImage: "checkmark.seal.fill",
            tint: .green,
            isSelected: statusFilter == .synced
        ) {
            withAnimation(.easeInOut(duration: 0.15)) {
                statusFilter = statusFilter == .synced ? .all : .synced
            }
        }

        CTXInteractiveKpiCard(
            title: "Out of Sync",
            value: "\(outOfSyncCount)",
            subtitle: "Pending reconciliation",
            systemImage: "arrow.triangle.2.circlepath",
            tint: outOfSyncCount > 0 ? .orange : .secondary,
            isSelected: statusFilter == .outOfSync
        ) {
            withAnimation(.easeInOut(duration: 0.15)) {
                statusFilter = statusFilter == .outOfSync ? .all : .outOfSync
            }
        }

        CTXInteractiveKpiCard(
            title: "Needs Attention",
            value: "\(attentionCount)",
            subtitle: "Degraded or progressing",
            systemImage: "exclamationmark.triangle.fill",
            tint: attentionCount > 0 ? .red : .secondary,
            isSelected: statusFilter == .degraded
        ) {
            withAnimation(.easeInOut(duration: 0.15)) {
                statusFilter = statusFilter == .degraded ? .all : .degraded
            }
        }
    }

    // MARK: - Main Split Content

    @ViewBuilder
    private var mainContentArea: some View {
        if viewModel.isLoadingGitOps && viewModel.gitOpsResult == nil {
            CTXGlassPanel {
                CTXLoadingStateView(
                    title: "Discovering GitOps Controllers",
                    message: "Checking ArgoCD Applications, Flux CD Kustomizations/HelmReleases, and Flagger Canaries...",
                    centered: true
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let result = viewModel.gitOpsResult, result.status != .reachable && result.items.isEmpty {
            CTXDiagnosticCard(
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "GitOps Discovery Issue",
                message: result.diagnostic?.stderrSummary ?? "Unable to query GitOps custom resources.",
                diagnosticSummary: result.diagnostic?.safeSummary,
                retry: { viewModel.loadGitOps(bypassCache: true) }
            )
        } else if scopedItems.isEmpty {
            CTXGlassPanel {
                CTXEmptyStateView(
                    title: "No GitOps Applications",
                    message: viewModel.gitOpsEmptyMessage,
                    systemImage: "arrow.triangle.branch"
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredItems.isEmpty {
            CTXGlassPanel {
                VStack(spacing: 12) {
                    CTXEmptyStateView(
                        title: "No Matching Applications",
                        message: "No applications match the active filter.",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    Button("Reset Filters") {
                        selectedProvider = "All"
                        statusFilter = .all
                        searchText = ""
                    }
                    .buttonStyle(CTXSecondaryButton())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            GeometryReader { geo in
                let totalW = geo.size.width
                let masterW = min(max(totalW * 0.34, 260), 390)

                HStack(alignment: .top, spacing: 12) {
                    if !isMasterListCollapsed {
                        applicationsListSidebar
                            .frame(width: masterW)
                            .frame(maxHeight: .infinity)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    applicationDetailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Left Master Sidebar

    private var applicationsListSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("APPLICATIONS (\(filteredItems.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
                if statusFilter != .all || selectedProvider != "All" {
                    Button("Clear") {
                        statusFilter = .all
                        selectedProvider = "All"
                    }
                    .buttonStyle(CTXInlineActionButton())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider().opacity(0.4)

            ScrollView(.vertical) {
                LazyVStack(spacing: 6) {
                    ForEach(filteredItems) { item in
                        applicationRowCard(item)
                    }
                }
                .padding(8)
            }
        }
        .ctxGlassCard(cornerRadius: 12)
    }

    private func applicationRowCard(_ item: GitOpsApplicationItem) -> some View {
        let isSelected = viewModel.selectedGitOpsApp?.id == item.id
        let targetNS = (!item.destinationNamespace.isEmpty && item.destinationNamespace != KubernetesGitOpsService.unknownValue)
            ? item.destinationNamespace
            : item.namespace

        return Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                viewModel.selectedGitOpsApp = item
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 7) {
                    GitOpsBrandIconView(provider: item.provider, size: 16)

                    Text(item.name)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(item.kind)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(providerTint(item.provider))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(providerTint(item.provider).opacity(0.12), in: Capsule())
                }

                HStack(spacing: 6) {
                    CTXSemanticPill(
                        text: item.syncStatus,
                        systemImage: syncIcon(item.syncStatus),
                        tint: syncTint(item.syncStatus)
                    )
                    CTXSemanticPill(
                        text: item.healthStatus,
                        systemImage: healthIcon(item.healthStatus),
                        tint: healthTint(item.healthStatus)
                    )
                    Spacer(minLength: 4)
                    Text(item.age)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Label(targetNS, systemImage: "square.grid.2x2")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(shortRepoOrSource(item))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let weight = item.canaryWeightPercent, item.provider == "Flagger" {
                    ProgressView(value: Double(weight), total: 100)
                        .tint(healthTint(item.healthStatus))
                        .controlSize(.small)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.025))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.2 : 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Detail Inspector Pane

    @ViewBuilder
    private var applicationDetailPane: some View {
        if let app = viewModel.selectedGitOpsApp {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    detailHeaderCard(app)
                    sourceAndRevisionCard(app)
                    if app.provider == "Flagger" {
                        flaggerCanaryCard(app)
                    }
                    if !app.message.isEmpty {
                        controllerMessageCard(app)
                    }
                    if !app.managedResources.isEmpty {
                        managedResourcesSection(app)
                    }
                }
                .padding(14)
            }
            .ctxGlassCard(cornerRadius: 12)
        } else {
            CTXGlassPanel {
                CTXEmptyStateView(
                    title: "Select an Application",
                    message: "Choose an ArgoCD Application, Flux resource, or Flagger Canary to inspect its delivery pipeline.",
                    systemImage: "arrow.triangle.branch"
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeaderCard(_ app: GitOpsApplicationItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    detailIdentityCluster(app)
                    Spacer(minLength: 8)
                    detailActionButtons(app)
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    detailIdentityCluster(app)
                    detailActionButtons(app)
                }
            }

            Divider().opacity(0.4)

            // Metadata Strip
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                metadataBrandCell(label: "PROVIDER & KIND", value: "\(app.provider) · \(app.kind)", provider: app.provider)
                metadataCell(label: "CONTROLLER NS", value: app.namespace, icon: "server.rack")
                metadataCell(
                    label: "TARGET NAMESPACE",
                    value: (!app.destinationNamespace.isEmpty && app.destinationNamespace != KubernetesGitOpsService.unknownValue)
                        ? app.destinationNamespace
                        : app.namespace,
                    icon: "scope"
                )
                metadataCell(label: "SOURCE TYPE", value: app.sourceKind.rawValue + (app.additionalSourceCount > 0 ? " +\(app.additionalSourceCount)" : ""), icon: "shippingbox")
                if app.managedBy != KubernetesGitOpsService.unknownValue {
                    metadataCell(label: "MANAGED BY", value: app.managedBy, icon: "person.2.badge.gearshape")
                }
                metadataCell(label: "AGE", value: app.age, icon: "clock")
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        }
    }

    private func detailIdentityCluster(_ app: GitOpsApplicationItem) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                appIdentityLeading(app)
                CTXSemanticPill(
                    text: app.syncStatus,
                    systemImage: syncIcon(app.syncStatus),
                    tint: syncTint(app.syncStatus)
                )
                CTXSemanticPill(
                    text: app.healthStatus,
                    systemImage: healthIcon(app.healthStatus),
                    tint: healthTint(app.healthStatus)
                )
            }
            VStack(alignment: .leading, spacing: 6) {
                appIdentityLeading(app)
                HStack(spacing: 6) {
                    CTXSemanticPill(
                        text: app.syncStatus,
                        systemImage: syncIcon(app.syncStatus),
                        tint: syncTint(app.syncStatus)
                    )
                    CTXSemanticPill(
                        text: app.healthStatus,
                        systemImage: healthIcon(app.healthStatus),
                        tint: healthTint(app.healthStatus)
                    )
                }
            }
        }
    }

    private func appIdentityLeading(_ app: GitOpsApplicationItem) -> some View {
        HStack(spacing: 8) {
            GitOpsBrandIconView(provider: app.provider, size: 24)

            if isMasterListCollapsed {
                Menu {
                    ForEach(filteredItems) { item in
                        Button {
                            viewModel.selectedGitOpsApp = item
                        } label: {
                            Text("\(item.name) (\(item.provider))")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(.title3, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Text(app.name)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            CTXCopyIconButton(value: app.name)
        }
    }

    private func detailActionButtons(_ app: GitOpsApplicationItem) -> some View {
        HStack(spacing: 8) {
            // Primary Sync / Reconcile Button
            Button {
                viewModel.syncGitOpsApp(app, prune: true)
            } label: {
                HStack(spacing: 5) {
                    if viewModel.isPerformingGitOpsAction {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: app.provider == "Flagger" ? "arrow.up.circle.fill" : "arrow.triangle.2.circlepath")
                    }
                    Text(app.provider == "Flagger" ? "Promote" : "Sync")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(CTXPrimaryButton())
            .disabled(viewModel.isPerformingGitOpsAction)
            .help(app.provider == "Flagger" ? "Manually promote Canary to 100%" : "Trigger controller sync (prune=true)")

            // Refresh Menu / Button
            if app.provider == "ArgoCD" {
                Menu {
                    Button {
                        viewModel.refreshGitOpsApp(app, hard: false)
                    } label: {
                        Label("Normal Refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        viewModel.refreshGitOpsApp(app, hard: true)
                    } label: {
                        Label("Hard Refresh (Clear Cache)", systemImage: "arrow.clockwise.circle.fill")
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(viewModel.isPerformingGitOpsAction)
                .help("Refresh target and sync state from repository")
            } else if app.provider == "Flux CD" {
                Button {
                    viewModel.refreshGitOpsApp(app, hard: false)
                } label: {
                    Label("Reconcile", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(CTXSecondaryButton())
                .disabled(viewModel.isPerformingGitOpsAction)
                .help("Trigger immediate Flux reconciliation")
            }

            // Suspend / Resume Button
            if app.provider == "Flux CD" || app.provider == "Flagger" {
                let isSuspended = app.syncStatus.lowercased() == "suspended"
                Button {
                    viewModel.toggleSuspendGitOpsApp(app)
                } label: {
                    Label(isSuspended ? "Resume" : "Suspend", systemImage: isSuspended ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(CTXSecondaryButton())
                .disabled(viewModel.isPerformingGitOpsAction)
                .help(isSuspended ? "Resume automated reconciliation" : "Suspend automated reconciliation")
            }

            if let row = viewModel.gitOpsList?.rows.first(where: { $0.id == app.id }) {
                Button {
                    viewModel.selectResource(row, in: .gitops)
                } label: {
                    Label("Inspect YAML", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(CTXSecondaryButton())
            }
        }
    }

    // MARK: - Source & Revision Pipeline Card

    private func sourceAndRevisionCard(_ app: GitOpsApplicationItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SOURCE & REVISION PIPELINE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    repositoryBox(app)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    revisionComparisonBox(app)
                }
                VStack(alignment: .leading, spacing: 10) {
                    repositoryBox(app)
                    revisionComparisonBox(app)
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.75)
        }
    }

    private func repositoryBox(_ app: GitOpsApplicationItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if app.sourceKind == .helmChart {
                    HelmBrandIconView(size: 13)
                } else if app.repoURL.lowercased().contains("github") || app.repoURL.lowercased().contains("git") {
                    CTXBrandSVGIcon(assetName: "github", size: 13, fallbackSystemImage: "link", fallbackTint: Color.accentColor)
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text("REPOSITORY / SOURCE")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let webURL = browsableRepoURL(app.repoURL) {
                    Button {
                        NSWorkspace.shared.open(webURL)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open Repository in Browser")
                }
                if app.repoURL != KubernetesGitOpsService.unknownValue {
                    CTXCopyIconButton(value: app.repoURL)
                }
            }
            Text(app.repoURL)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                if app.path != KubernetesGitOpsService.unknownValue && !app.path.isEmpty {
                    Label(app.path, systemImage: "folder")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if app.chart != KubernetesGitOpsService.unknownValue && !app.chart.isEmpty {
                    Label(app.chart, systemImage: "shippingbox.fill")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func revisionComparisonBox(_ app: GitOpsApplicationItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TARGET REVISION")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                CTXSemanticPill(
                    text: app.targetRevision,
                    systemImage: "target",
                    tint: .blue,
                    monospaced: true
                )
            }

            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("SYNCED REVISION")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                    if app.syncedRevision != KubernetesGitOpsService.unknownValue {
                        CTXCopyIconButton(value: app.syncedRevision)
                    }
                }
                CTXSemanticPill(
                    text: app.syncedRevision,
                    systemImage: "number",
                    tint: isSynced(app) ? .green : .orange,
                    monospaced: true
                )
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Flagger Canary Card

    private func flaggerCanaryCard(_ app: GitOpsApplicationItem) -> some View {
        let weight = app.canaryWeightPercent ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("PROGRESSIVE CANARY TRAFFIC SHIFT", systemImage: "dial.medium.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(app.syncedRevision) (\(app.targetRevision))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(healthTint(app.healthStatus))
            }
            ProgressView(value: Double(weight), total: 100)
                .tint(healthTint(app.healthStatus))
        }
        .padding(12)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Controller Status Message

    private func controllerMessageCard(_ app: GitOpsApplicationItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isDegradedOrAttention(app) ? "exclamationmark.Bubble.fill" : "info.circle.fill")
                .foregroundStyle(isDegradedOrAttention(app) ? .orange : .secondary)
                .font(.system(size: 13, weight: .semibold))
            Text(app.message)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            (isDegradedOrAttention(app) ? Color.orange : Color.secondary).opacity(0.09),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    // MARK: - Managed Kubernetes Resources Table

    private func managedResourcesSection(_ app: GitOpsApplicationItem) -> some View {
        let filteredRes = app.managedResources.filter { res in
            guard !resourceSearchText.isEmpty else { return true }
            let q = resourceSearchText.lowercased()
            return res.name.lowercased().contains(q)
                || res.kind.lowercased().contains(q)
                || res.namespace.lowercased().contains(q)
        }

        return VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("MANAGED RESOURCES (\(app.managedResources.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    Spacer()
                    if app.managedResources.count > 4 {
                        CTXSearchField(placeholder: "Filter resources...", text: $resourceSearchText)
                            .frame(width: 200)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("MANAGED RESOURCES (\(app.managedResources.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    if app.managedResources.count > 4 {
                        CTXSearchField(placeholder: "Filter resources...", text: $resourceSearchText)
                    }
                }
            }

            LazyVStack(spacing: 6) {
                ForEach(filteredRes) { res in
                    HStack(spacing: 10) {
                        Text(res.kind.uppercased())
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                        Text(res.name)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if !res.namespace.isEmpty && res.namespace != KubernetesGitOpsService.unknownValue {
                            Text(res.namespace)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        if res.syncStatus != KubernetesGitOpsService.unknownValue {
                            CTXSemanticPill(text: res.syncStatus, tint: syncTint(res.syncStatus))
                        }
                        if res.healthStatus != KubernetesGitOpsService.unknownValue {
                            CTXSemanticPill(text: res.healthStatus, tint: healthTint(res.healthStatus))
                        }
                        if let navKind = navigableKind(for: res.kind) {
                            Button {
                                let targetNS: String? = (res.namespace.isEmpty || res.namespace == KubernetesGitOpsService.unknownValue)
                                    ? ((app.destinationNamespace.isEmpty || app.destinationNamespace == KubernetesGitOpsService.unknownValue) ? app.namespace : app.destinationNamespace)
                                    : res.namespace
                                Task {
                                    await viewModel.navigateToResource(
                                        kind: navKind,
                                        name: res.name,
                                        namespace: targetNS,
                                        tab: .overview
                                    )
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text("Inspect")
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("Inspect \(res.kind)/\(res.name)")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.75)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.75)
        }
    }

    // MARK: - Helpers

    private func metadataBrandCell(label: String, value: String, provider: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                GitOpsBrandIconView(provider: provider, size: 11)
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private func metadataCell(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private func bannerRow(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.caption.weight(.bold))
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 0.75)
        }
    }

    private func shortRepoOrSource(_ item: GitOpsApplicationItem) -> String {
        if item.sourceKind == .helmChart && item.chart != KubernetesGitOpsService.unknownValue {
            return item.chart
        }
        let cleaned = item.repoURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "oci://", with: "")
            .replacingOccurrences(of: ".git", with: "")
        let parts = cleaned.split(separator: "/")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: "/")
        }
        return cleaned
    }

    private func isSynced(_ item: GitOpsApplicationItem) -> Bool {
        item.syncStatus.lowercased() == "synced"
    }

    private func isOutOfSync(_ item: GitOpsApplicationItem) -> Bool {
        item.syncStatus.lowercased() == "outofsync"
    }

    private func isHealthy(_ item: GitOpsApplicationItem) -> Bool {
        ["healthy", "synced", "succeeded"].contains(item.healthStatus.lowercased())
    }

    private func isDegradedOrAttention(_ item: GitOpsApplicationItem) -> Bool {
        let h = item.healthStatus.lowercased()
        return !["healthy", "synced", "suspended", KubernetesGitOpsService.unknownValue].contains(h)
    }

    private func providerIcon(_ provider: String) -> String {
        switch provider {
        case "ArgoCD": return "arrow.triangle.pull"
        case "Flux CD": return "waveform.path.ecg"
        case "Flagger": return "flag.checkered"
        default: return "arrow.triangle.branch"
        }
    }

    private func providerTint(_ provider: String) -> Color {
        switch provider {
        case "ArgoCD": return .orange
        case "Flux CD": return .indigo
        case "Flagger": return .mint
        default: return .accentColor
        }
    }

    private func syncIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "synced": return "checkmark.circle.fill"
        case "outofsync": return "arrow.triangle.2.circlepath"
        case "suspended": return "pause.circle.fill"
        case "progressing": return "clock.arrow.2.circlepath"
        default: return "questionmark.circle"
        }
    }

    private func syncTint(_ status: String) -> Color {
        switch status.lowercased() {
        case "synced": return .green
        case "outofsync": return .orange
        case "suspended": return .secondary
        case "progressing": return .blue
        default: return .secondary
        }
    }

    private func healthIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "healthy", "succeeded": return "heart.fill"
        case "progressing", "promoting", "waiting": return "bolt.heart.fill"
        case "suspended": return "pause.circle"
        case "degraded", "failed", "missing": return "heart.slash.fill"
        default: return "circle.dotted"
        }
    }

    private func healthTint(_ status: String) -> Color {
        switch status.lowercased() {
        case "healthy", "succeeded": return .green
        case "progressing", "promoting", "waiting", "initializing": return .blue
        case "suspended": return .secondary
        case let s where s != KubernetesGitOpsService.unknownValue: return .red
        default: return .secondary
        }
    }

    private func browsableRepoURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") else { return nil }
        let clean = trimmed.hasSuffix(".git") ? String(trimmed.dropLast(4)) : trimmed
        return URL(string: clean)
    }

    private func navigableKind(for rawKind: String) -> KubernetesResourceKind? {
        switch rawKind.lowercased() {
        case "pod", "pods": return .pods
        case "deployment", "statefulset", "daemonset", "replicaset": return .workloads
        case "service", "services": return .services
        case "ingress": return .ingress
        case "configmap": return .configMaps
        case "secret": return .secretMetadata
        case "persistentvolumeclaim", "pvc": return .pvc
        case "horizontalpodautoscaler", "hpa": return .hpa
        case "cronjob", "job": return .cronJobs
        case "node": return .nodes
        case "namespace": return .namespaces
        default: return nil
        }
    }
}
