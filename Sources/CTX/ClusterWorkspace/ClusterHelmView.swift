import AppKit
import CTXCore
import SwiftUI

/// Authentic Apple-grade Helm Center & Releases Explorer for CTX.
///
/// Fully responsive across all window and screen sizes:
/// - Dynamic collapsible master list with ⌘-friendly toggle button.
/// - Fluid detail pane adapting to any window width without clipping.
/// - Synchronized responsive revision table with safe horizontal scrolling for narrow views.
/// - Dedicated Revision Inspector Card for metadata inspection.
/// - Authentic Helm inspection: User Values vs All Computed Values, rendered
///   Kubernetes Manifests with interactive Kind breakdown chips, and Revision Timeline.
/// - Monospaced Code Viewer with line gutters and syntax coloring.
struct ClusterHelmView: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel
    @State private var searchText = ""
    @State private var selectedStatusFilter = "All"
    @State private var codeSearchText = ""
    @State private var selectedKindFilter: String? = nil
    @State private var isMasterListCollapsed = false
    @State private var selectedRevision: HelmRevisionItem? = nil

    private var releases: [HelmReleaseItem] {
        viewModel.helmResult?.items ?? []
    }

    private var availableStatuses: [String] {
        let set = Set(releases.map { $0.status.lowercased() })
        return ["All"] + set.sorted()
    }

    private var filteredReleases: [HelmReleaseItem] {
        releases.filter { item in
            let matchesStatus = selectedStatusFilter == "All" || item.status.lowercased() == selectedStatusFilter.lowercased()
            guard matchesStatus else { return false }
            if searchText.isEmpty { return true }
            let query = searchText.lowercased()
            return item.name.lowercased().contains(query)
                || item.chart.lowercased().contains(query)
                || item.namespace.lowercased().contains(query)
                || item.appVersion.lowercased().contains(query)
        }
    }

    private var deployedCount: Int {
        releases.filter { $0.status.lowercased() == "deployed" }.count
    }

    private var failedCount: Int {
        releases.filter { $0.status.lowercased() == "failed" }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar
            mainSplitContent
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let notice = viewModel.helmSourceNotice {
                    CTXFloatingToast(
                        text: notice,
                        systemImage: "info.circle.fill",
                        tint: .blue
                    )
                }
            }
            .padding(.top, 10)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: viewModel.helmSourceNotice)
        }
        .onAppear {
            if viewModel.helmResult == nil {
                viewModel.loadHelm()
            }
        }
    }

    // MARK: - Header Bar (Clean, Unified, With Sidebar Toggle)

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            // Master list toggle button (Apple HIG sidebar style)
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isMasterListCollapsed.toggle()
                }
            } label: {
                Image(systemName: isMasterListCollapsed ? "sidebar.left" : "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isMasterListCollapsed ? Color.accentColor : Color.secondary)
                    .padding(6)
                    .background(
                        isMasterListCollapsed ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help(isMasterListCollapsed ? "Show Releases List" : "Hide Releases List")

            HStack(spacing: 8) {
                HelmBrandIconView(size: 22)
                Text("Helm Releases")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                Text("\(releases.count)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(.blue)
            }

            Spacer(minLength: 12)

            // Status Filter Menu
            statusFilterMenu

            // Search Field
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Filter releases or charts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .frame(minWidth: 100, maxWidth: 180)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 0.75)
            }
        }
    }

    private var scopeDescription: String {
        switch viewModel.selectedNamespace {
        case .allNamespaces:
            return "Cluster-wide scope • \(deployedCount) deployed\(failedCount > 0 ? ", \(failedCount) failed" : "")"
        case .defaultNamespace:
            return "Namespace: default • \(releases.count) releases"
        case .namespace(let ns):
            return "Namespace: \(ns) • \(releases.count) releases"
        }
    }

    private var statusFilterMenu: some View {
        Menu {
            Button("All Statuses (\(releases.count))") {
                selectedStatusFilter = "All"
            }
            ForEach(availableStatuses.filter { $0 != "All" }, id: \.self) { status in
                let count = releases.filter { $0.status.lowercased() == status }.count
                Button("\(status.capitalized) (\(count))") {
                    selectedStatusFilter = status
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.caption)
                Text(selectedStatusFilter == "All" ? "Status: All" : selectedStatusFilter.capitalized)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func sourceNoticeBanner(_ notice: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
            Text(notice)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.75)
        }
    }

    // MARK: - Main Split Content (Responsive Geometry)

    private var mainSplitContent: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let isCompact = totalWidth < 850
            let masterWidth: CGFloat = isCompact ? 250 : 280

            HStack(alignment: .top, spacing: 12) {
                // Left Master List
                if !isMasterListCollapsed {
                    masterListView
                        .frame(width: masterWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Right Inspector / Detail View
                let detailWidth = isMasterListCollapsed ? totalWidth : max(280, totalWidth - masterWidth - 12)
                detailInspectorView(isMasterCollapsed: isMasterListCollapsed, availableWidth: detailWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Master List View

    private var masterListView: some View {
        CTXGlassPanel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // List Header
                HStack {
                    Text("RELEASES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(filteredReleases.count) of \(releases.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider().opacity(0.4)

                if filteredReleases.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "shippingbox")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text(emptyTitle)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(emptySubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(filteredReleases) { release in
                                releaseRowCard(release)
                            }
                        }
                        .padding(6)
                    }
                }
            }
        }
    }

    private var emptyTitle: String {
        if releases.isEmpty {
            return "No Helm Releases"
        }
        return "No Matching Releases"
    }

    private var emptySubtitle: String {
        if releases.isEmpty {
            return viewModel.helmEmptyMessage
        }
        return "No release matches your filter criteria."
    }

    private func releaseRowCard(_ release: HelmReleaseItem) -> some View {
        let isSelected = viewModel.selectedHelmRelease?.id == release.id
        return Button {
            viewModel.selectHelmRelease(release)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                // Row Top: Name & Namespace
                HStack(spacing: 6) {
                    Text(release.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(release.namespace)
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Row Middle: Chart & App Version
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.blue)
                    Text(release.chart == KubernetesGitOpsService.unknownValue ? "Storage Secret" : release.chart)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if release.appVersion != KubernetesGitOpsService.unknownValue && !release.appVersion.isEmpty {
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("v\(release.appVersion)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Row Bottom: Status Dot, Revision, Updated
                HStack(spacing: 6) {
                    statusChip(release.status)
                    Text("rev \(release.revision)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(release.updated)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.02),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.14),
                        lineWidth: isSelected ? 1.25 : 0.75
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func statusChip(_ status: String) -> some View {
        let (dotColor, text) = statusStyle(status)
        return HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 5.5, height: 5.5)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(dotColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(dotColor.opacity(0.12), in: Capsule())
    }

    private func statusStyle(_ status: String) -> (Color, String) {
        let lower = status.lowercased()
        if lower == "deployed" {
            return (.green, "Deployed")
        } else if lower.contains("failed") {
            return (.red, "Failed")
        } else if lower.contains("pending") {
            return (.orange, status.capitalized)
        } else if lower.contains("uninstall") {
            return (.secondary, "Uninstalled")
        } else if lower.contains("superseded") {
            return (.secondary, "Superseded")
        }
        return (.secondary, status.capitalized)
    }

    // MARK: - Detail Inspector View (Responsive)

    private func detailInspectorView(isMasterCollapsed: Bool, availableWidth: CGFloat) -> some View {
        CTXGlassPanel(padding: 0) {
            if let release = viewModel.selectedHelmRelease {
                VStack(alignment: .leading, spacing: 0) {
                    // Release Header (Responsive)
                    detailHeader(release, isMasterCollapsed: isMasterCollapsed, availableWidth: availableWidth)

                    Divider().opacity(0.4)

                    // Tab Switcher
                    detailTabBar

                    Divider().opacity(0.4)

                    // Tab Content
                    detailTabContent(release, availableWidth: availableWidth)
                }
            } else {
                noSelectionPlaceholder(isMasterCollapsed: isMasterCollapsed)
            }
        }
    }

    private func noSelectionPlaceholder(isMasterCollapsed: Bool) -> some View {
        VStack(spacing: 12) {
            Spacer()
            HelmBrandIconView(size: 44)
            Text("No Release Selected")
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
            Text("Select a Helm release on the left to inspect its values, rendered manifest, and revision history.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            if isMasterCollapsed {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isMasterListCollapsed = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sidebar.left")
                        Text("Show Releases List")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailHeader(_ release: HelmReleaseItem, isMasterCollapsed: Bool, availableWidth: CGFloat) -> some View {
        let isNarrow = availableWidth < 620

        return VStack(alignment: .leading, spacing: isNarrow ? 7 : 0) {
            HStack(alignment: .center, spacing: 10) {
                if isMasterCollapsed {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isMasterListCollapsed = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sidebar.left")
                            Text("Releases (\(releases.count))")
                        }
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Show Releases List")
                }

                HelmBrandIconView(size: 24)

                HStack(spacing: 6) {
                    Text(release.name)
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    CTXCopyIconButton(value: release.name)

                    statusChip(release.status)
                }

                if !isNarrow {
                    Spacer(minLength: 8)
                    metadataBadgesGroup(release)
                }
            }

            if isNarrow {
                HStack {
                    Text("Namespace: \(release.namespace)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    metadataBadgesGroup(release)
                }
            } else {
                Text("Namespace: \(release.namespace)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func metadataBadgesGroup(_ release: HelmReleaseItem) -> some View {
        HStack(spacing: 6) {
            if release.chart != KubernetesGitOpsService.unknownValue {
                metadataBadge(title: "Chart", value: release.chart, systemImage: "shippingbox.fill")
            }
            if release.appVersion != KubernetesGitOpsService.unknownValue && !release.appVersion.isEmpty {
                metadataBadge(title: "App", value: release.appVersion, systemImage: "tag.fill")
            }
            metadataBadge(title: "Rev", value: "\(release.revision)", systemImage: "arrow.counterclockwise")
        }
    }

    private func metadataBadge(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9))
                .foregroundStyle(Color.accentColor)
            Text("\(title): \(value)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - Native Segmented Tab Bar & Controls

    private var detailTabBar: some View {
        HStack(spacing: 10) {
            // Unified Segmented Pill Tab Bar
            HStack(spacing: 2) {
                ForEach(ClusterWorkspaceViewModel.HelmDetailTab.allCases) { tab in
                    let isSelected = viewModel.helmDetailTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.setHelmTab(tab)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tabIcon(tab))
                                .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                            Text(tab.rawValue)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(
                            isSelected ? Color.primary.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 0.75)
            }
            .fixedSize()

            Spacer()

            // Values Tab: User vs All Computed toggle
            if viewModel.helmDetailTab == .values {
                HStack(spacing: 2) {
                    Button {
                        if viewModel.helmIncludeAllValues {
                            viewModel.toggleHelmAllValues()
                        }
                    } label: {
                        Text("User Values")
                            .font(.system(size: 10.5, weight: !viewModel.helmIncludeAllValues ? .semibold : .regular))
                            .foregroundStyle(!viewModel.helmIncludeAllValues ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                !viewModel.helmIncludeAllValues ? Color.primary.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        if !viewModel.helmIncludeAllValues {
                            viewModel.toggleHelmAllValues()
                        }
                    } label: {
                        Text("All Computed (--all)")
                            .font(.system(size: 10.5, weight: viewModel.helmIncludeAllValues ? .semibold : .regular))
                            .foregroundStyle(viewModel.helmIncludeAllValues ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                viewModel.helmIncludeAllValues ? Color.primary.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 0.75)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func tabIcon(_ tab: ClusterWorkspaceViewModel.HelmDetailTab) -> String {
        switch tab {
        case .values: return "slider.horizontal.3"
        case .manifest: return "doc.text.fill"
        case .history: return "clock.arrow.circlepath"
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func detailTabContent(_ release: HelmReleaseItem, availableWidth: CGFloat) -> some View {
        if viewModel.isLoadingHelmDetail {
            CTXLoadingStateView(
                title: "Loading \(viewModel.helmDetailTab.rawValue)...",
                message: "Querying Helm release...",
                centered: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if let error = viewModel.helmDetailError {
            VStack {
                Spacer()
                CTXDiagnosticCard(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: "Could not load \(viewModel.helmDetailTab.rawValue)",
                    message: error,
                    retry: { viewModel.loadSelectedHelmDetail(force: true) }
                )
                .padding(20)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewModel.helmDetailTab {
            case .values:
                valuesTabView
            case .manifest:
                manifestTabView
            case .history:
                historyTabView(release, availableWidth: availableWidth)
            }
        }
    }

    // MARK: - Values Tab View

    private var valuesTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let yaml = viewModel.helmValuesYAML {
                let lineCount = yaml.split(separator: "\n", omittingEmptySubsequences: false).count
                HStack(spacing: 8) {
                    Text(viewModel.helmIncludeAllValues ? "All Computed Values (\(lineCount) lines)" : "User Values (\(lineCount) lines)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // In-code search field
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("Search in values...", text: $codeSearchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .frame(width: 140)
                        if !codeSearchText.isEmpty {
                            Button {
                                codeSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 0.75)
                    }

                    // Native CTX Copy Icon Button
                    CTXCopyIconButton(value: yaml)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)

                Divider().opacity(0.3)

                codeViewer(yaml)
            } else if viewModel.isLoadingHelmDetail {
                CTXLoadingStateView(
                    title: "Loading Helm values...",
                    message: "Querying values for release...",
                    centered: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Custom Values Configured")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("This release uses default values packaged with its chart, with no custom user overrides.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)

                    Button {
                        viewModel.toggleHelmAllValues()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Inspect All Computed Values (--all)")
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 6)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Manifest Tab View with Organized Kind Filter & Search

    private var manifestTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let yaml = viewModel.helmManifestYAML {
                let kinds = Self.extractManifestKinds(from: yaml)
                let totalResources = kinds.map(\.count).reduce(0, +)
                let filteredYaml = manifestContentForKind(yaml: yaml, kind: selectedKindFilter)

                HStack(spacing: 8) {
                    if !kinds.isEmpty {
                        // Organized Kind Filter Dropdown
                        Menu {
                            Button {
                                selectedKindFilter = nil
                            } label: {
                                HStack {
                                    Text("All Resources (\(totalResources))")
                                    if selectedKindFilter == nil {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Divider()
                            ForEach(kinds, id: \.kind) { item in
                                Button {
                                    selectedKindFilter = item.kind
                                } label: {
                                    HStack {
                                        Text("\(item.kind) (\(item.count))")
                                        if selectedKindFilter == item.kind {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: selectedKindFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(selectedKindFilter != nil ? Color.accentColor : .secondary)
                                Text(selectedKindFilter == nil ? "Filter: All Resources (\(totalResources))" : "Kind: \(selectedKindFilter!) (\(kinds.first(where: { $0.kind == selectedKindFilter })?.count ?? 0))")
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(selectedKindFilter != nil ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        if selectedKindFilter != nil {
                            Button {
                                selectedKindFilter = nil
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Clear")
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    // In-code search field
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("Search in manifest...", text: $codeSearchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .frame(width: 140)
                        if !codeSearchText.isEmpty {
                            Button {
                                codeSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 0.75)
                    }

                    // Native CTX Copy Icon Button
                    CTXCopyIconButton(value: filteredYaml)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)

                Divider().opacity(0.3)

                codeViewer(yaml, kindFilter: selectedKindFilter)
            } else if viewModel.isLoadingHelmDetail {
                CTXLoadingStateView(
                    title: "Loading Helm manifest...",
                    message: "Querying rendered manifest...",
                    centered: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack {
                    Spacer()
                    Text("No manifest loaded")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func manifestContentForKind(yaml: String, kind: String?) -> String {
        guard let kind = kind, !kind.isEmpty else { return yaml }
        let rawLines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [String] = []
        var currentDocKind: String? = nil
        var currentDocLines: [String] = []

        let flushDoc = { (lines: inout [String], docKind: String?) in
            if docKind?.lowercased() == kind.lowercased() {
                if !result.isEmpty {
                    result.append("---")
                }
                result.append(contentsOf: lines)
            }
            lines.removeAll(keepingCapacity: true)
        }

        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                flushDoc(&currentDocLines, currentDocKind)
                currentDocKind = nil
            } else if trimmed.hasPrefix("kind:") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    currentDocKind = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            currentDocLines.append(line)
        }
        flushDoc(&currentDocLines, currentDocKind)
        return result.isEmpty ? yaml : result.joined(separator: "\n")
    }

    // MARK: - History Tab View (Responsive Table with Safe Horizontal Scrolling & Inspector)

    private enum HistoryColumns {
        static let revision: CGFloat = 65
        static let status: CGFloat = 85
        static let chart: CGFloat = 145
        static let appVersion: CGFloat = 75
        static let updated: CGFloat = 65
        static let actions: CGFloat = 85
    }

    private func historyTabView(_ release: HelmReleaseItem, availableWidth: CGFloat) -> some View {
        Group {
            if viewModel.helmHistory.isEmpty {
                if viewModel.isLoadingHelmDetail {
                    CTXLoadingStateView(
                        title: "Loading Helm history...",
                        message: "Querying release revisions...",
                        centered: true
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text("No History Available")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Revision history could not be retrieved for this release.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    let minTableWidth: CGFloat = 660
                    let tableWidth = max(availableWidth - 2, minTableWidth)
                    let needsHorizontalScroll = availableWidth < minTableWidth

                    ScrollView(needsHorizontalScroll ? [.horizontal, .vertical] : [.vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Table Header
                            historyTableHeader
                                .frame(width: tableWidth, alignment: .leading)

                            Divider().opacity(0.4)

                            // Table Rows
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.helmHistory) { item in
                                    let isActive = item.revision == release.revision
                                    let isSelected = (selectedRevision?.revision ?? release.revision) == item.revision
                                    Button {
                                        selectedRevision = item
                                    } label: {
                                        historyRow(item, isActive: isActive, isSelected: isSelected)
                                            .frame(width: tableWidth, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)

                                    Divider().opacity(0.18)
                                }
                            }
                        }
                        .frame(width: tableWidth, alignment: .topLeading)
                    }

                    // Bottom Selected Revision Inspector Panel
                    if let rev = selectedRevision ?? viewModel.helmHistory.first(where: { $0.revision == release.revision }) ?? viewModel.helmHistory.first {
                        Divider().opacity(0.4)
                        revisionInspectorFooter(rev, currentRelease: release)
                    }
                }
            }
        }
    }

    private var historyTableHeader: some View {
        HStack(spacing: 8) {
            Text("REVISION")
                .frame(width: HistoryColumns.revision, alignment: .leading)
            Text("STATUS")
                .frame(width: HistoryColumns.status, alignment: .leading)
            Text("CHART")
                .frame(width: HistoryColumns.chart, alignment: .leading)
            Text("APP VERSION")
                .frame(width: HistoryColumns.appVersion, alignment: .leading)
            Text("UPDATED")
                .frame(width: HistoryColumns.updated, alignment: .leading)
            Text("DESCRIPTION")
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            Text("ACTION")
                .frame(width: HistoryColumns.actions, alignment: .trailing)
        }
        .font(.system(size: 9.5, weight: .bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.04))
    }

    private func historyRow(_ item: HelmRevisionItem, isActive: Bool, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            // Revision Column: rev + small CURRENT pill
            HStack(spacing: 4) {
                Text("\(item.revision)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                if isActive {
                    Text("CURRENT")
                        .font(.system(size: 7.5, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                        .fixedSize()
                }
            }
            .frame(width: HistoryColumns.revision, alignment: .leading)

            // Status Column
            statusChip(item.status)
                .frame(width: HistoryColumns.status, alignment: .leading)

            // Chart Column
            HStack(spacing: 4) {
                Text(item.chart)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                CTXCopyIconButton(value: item.chart)
            }
            .frame(width: HistoryColumns.chart, alignment: .leading)

            // App Version Column
            Text(item.appVersion.isEmpty ? "-" : item.appVersion)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: HistoryColumns.appVersion, alignment: .leading)

            // Updated Column
            Text(item.updated)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: HistoryColumns.updated, alignment: .leading)

            // Description Column
            Text(item.description.isEmpty ? "-" : item.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

            // Read-only state marker. CTX does not mutate Helm releases.
            HStack {
                Spacer()
                if isActive {
                    Text("Active")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: HistoryColumns.actions, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.12)
                : (isActive ? Color.accentColor.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func revisionInspectorFooter(_ item: HelmRevisionItem, currentRelease: HelmReleaseItem) -> some View {
        let isActive = item.revision == currentRelease.revision

        return HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                .font(.system(size: 14))
                .foregroundStyle(isActive ? Color.green : Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Revision \(item.revision)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)

                    if isActive {
                        Text("Active")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.16), in: Capsule())
                            .foregroundStyle(.green)
                    }

                    Text("•  \(item.status.capitalized)  •  \(item.updated)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(item.description.isEmpty ? "No description recorded" : item.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.06))
    }

    // MARK: - Robust Monospaced Code Viewer with Line Gutter & Intrinsic Width

    private struct CodeLineItem: Identifiable {
        let id: Int
        let number: Int
        let text: String
        let isMatch: Bool
    }

    private func codeViewer(_ content: String, kindFilter: String? = nil) -> some View {
        let rawLines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let linesToDisplay: [CodeLineItem] = buildDisplayLines(rawLines: rawLines, kindFilter: kindFilter, searchQuery: codeSearchText)
        let gutterWidth: CGFloat = linesToDisplay.count > 999 ? 44 : 34

        return GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(linesToDisplay) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(item.number)")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.secondary.opacity(0.45))
                                .frame(width: gutterWidth, alignment: .trailing)

                            Text(item.text.isEmpty ? " " : item.text)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(codeLineColor(item.text))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 18, alignment: .leading)
                        .background(item.isMatch ? Color.yellow.opacity(0.22) : Color.clear)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minWidth: proxy.size.width, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.18))
    }

    private func buildDisplayLines(rawLines: [String], kindFilter: String?, searchQuery: String) -> [CodeLineItem] {
        let hasFilter = kindFilter != nil && !kindFilter!.isEmpty
        let hasSearch = !searchQuery.isEmpty

        var result: [CodeLineItem] = []
        result.reserveCapacity(rawLines.count)

        var currentDocKind: String? = nil
        var currentDocLines: [(number: Int, text: String)] = []

        let flushDoc = { (lines: inout [(number: Int, text: String)], kind: String?) in
            if !hasFilter || (kind?.lowercased() == kindFilter?.lowercased()) {
                for line in lines {
                    let isMatch = hasSearch && line.text.lowercased().contains(searchQuery.lowercased())
                    result.append(CodeLineItem(id: line.number, number: line.number, text: line.text, isMatch: isMatch))
                }
            }
            lines.removeAll(keepingCapacity: true)
        }

        if hasFilter {
            for (idx, line) in rawLines.enumerated() {
                let num = idx + 1
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "---" {
                    flushDoc(&currentDocLines, currentDocKind)
                    currentDocKind = nil
                } else if trimmed.hasPrefix("kind:") {
                    let parts = trimmed.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        currentDocKind = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
                currentDocLines.append((num, line))
            }
            flushDoc(&currentDocLines, currentDocKind)
        } else {
            for (idx, line) in rawLines.enumerated() {
                let num = idx + 1
                let isMatch = hasSearch && line.lowercased().contains(searchQuery.lowercased())
                result.append(CodeLineItem(id: num, number: num, text: line, isMatch: isMatch))
            }
        }

        return result
    }

    private func codeLineColor(_ line: String) -> Color {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            return .secondary.opacity(0.7)
        } else if trimmed.hasPrefix("---") {
            return .orange
        } else if trimmed.contains(":") {
            return .primary
        }
        return .primary
    }

    // MARK: - YAML Helpers

    static func extractManifestKinds(from yaml: String) -> [(kind: String, count: Int)] {
        var counts: [String: Int] = [:]
        let lines = yaml.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("kind:") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let kind = parts[1].trimmingCharacters(in: .whitespaces)
                    if !kind.isEmpty && !kind.hasPrefix("$") {
                        counts[kind, default: 0] += 1
                    }
                }
            }
        }
        return counts.map { (kind: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count || ($0.count == $1.count && $0.kind < $1.kind) }
    }
}


// MARK: - CNCF Helm Brand Icon View

struct HelmBrandIconView: View {
    var size: CGFloat = 26

    var body: some View {
        CTXBrandSVGIcon(
            assetName: "helm",
            size: size,
            fallbackSystemImage: "helm",
            fallbackTint: Color(hex: "2496ED")
        )
    }
}
