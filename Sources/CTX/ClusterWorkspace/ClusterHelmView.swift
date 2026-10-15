import AppKit
import CTXCore
import SwiftUI

/// Authentic Apple-grade Helm Center & Releases Explorer for CTX.
///
/// Complies strictly with Apple macOS Human Interface Guidelines:
/// - Split Master-Detail layout with fluid resizing and zero clutter.
/// - Crisp resolution-independent Helm vector branding and native SF Symbols.
/// - Authentic Helm inspection: User Values vs All Computed Values, rendered
///   Kubernetes Manifests with interactive Kind breakdown chips, and Revision Timeline.
/// - DevOps Production Operations: One-click safe revision Rollback with confirmation.
/// - Rock-solid Code Viewer: No text-wrapping/squishing, horizontal scrolling, syntax coloring.
struct ClusterHelmView: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel
    @State private var searchText = ""
    @State private var selectedStatusFilter = "All"
    @State private var codeSearchText = ""
    @State private var selectedKindFilter: String? = nil
    @State private var rollbackCandidate: HelmRevisionItem? = nil
    @State private var isShowingRollbackAlert = false

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
        VStack(alignment: .leading, spacing: 14) {
            headerBar
            if let notice = viewModel.helmSourceNotice {
                sourceNoticeBanner(notice)
            }
            if let success = viewModel.helmSuccessNotice {
                successNoticeBanner(success)
            }
            mainSplitContent
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if viewModel.helmResult == nil {
                viewModel.loadHelm()
            }
        }
        .alert("Roll Back Helm Release?", isPresented: $isShowingRollbackAlert, presenting: rollbackCandidate) { target in
            Button("Cancel", role: .cancel) {
                rollbackCandidate = nil
            }
            Button("Roll Back to Rev \(target.revision)", role: .destructive) {
                if let release = viewModel.selectedHelmRelease {
                    Task {
                        await viewModel.rollbackHelmRelease(release, toRevision: target.revision)
                    }
                }
                rollbackCandidate = nil
            }
        } message: { target in
            if let release = viewModel.selectedHelmRelease {
                Text("Are you sure you want to roll back '\(release.name)' in namespace '\(release.namespace)' to revision \(target.revision)? This executes 'helm rollback' directly against the cluster.")
            } else {
                Text("Confirm rollback to revision \(target.revision).")
            }
        }
    }

    // MARK: - Header Bar (Clean, Unified, No Duplicate Reload Icon)

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 10) {
                HelmBrandIconView(size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Helm Releases")
                            .font(.system(.title3, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("\(releases.count)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.16), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    Text(scopeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Status Filter Menu
            statusFilterMenu

            // Search Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Filter releases or charts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .frame(width: 180)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.75)
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
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
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

    private func successNoticeBanner(_ notice: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(notice)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                viewModel.helmSuccessNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.green.opacity(0.3), lineWidth: 0.75)
        }
    }

    // MARK: - Main Split Content

    private var mainSplitContent: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left Master List
            masterListView
                .frame(minWidth: 320, idealWidth: 350, maxWidth: 380)

            // Right Inspector / Detail View
            detailInspectorView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Master List View

    private var masterListView: some View {
        CTXGlassPanel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // List Header
                HStack {
                    Text("RELEASES")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(filteredReleases.count) of \(releases.count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().opacity(0.4)

                if filteredReleases.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "shippingbox")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text(emptyTitle)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(emptySubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filteredReleases) { release in
                                releaseRowCard(release)
                            }
                        }
                        .padding(8)
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
            VStack(alignment: .leading, spacing: 6) {
                // Row Top: Name & Namespace
                HStack(spacing: 6) {
                    Text(release.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(release.namespace)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                // Row Middle: Chart & App Version
                HStack(spacing: 5) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                    Text(release.chart == KubernetesGitOpsService.unknownValue ? "Storage Secret" : release.chart)
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if release.appVersion != KubernetesGitOpsService.unknownValue && !release.appVersion.isEmpty {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text("v\(release.appVersion)")
                            .font(.caption2.weight(.regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Row Bottom: Status Dot, Revision, Updated
                HStack(spacing: 8) {
                    statusChip(release.status)
                    Text("rev \(release.revision)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(release.updated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.02),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.15),
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
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(dotColor)
        }
        .padding(.horizontal, 7)
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

    // MARK: - Detail Inspector View

    private var detailInspectorView: some View {
        CTXGlassPanel(padding: 0) {
            if let release = viewModel.selectedHelmRelease {
                VStack(alignment: .leading, spacing: 0) {
                    // Release Header
                    detailHeader(release)

                    Divider().opacity(0.4)

                    // Tab Switcher
                    detailTabBar

                    Divider().opacity(0.4)

                    // Tab Content
                    detailTabContent(release)
                }
            } else {
                noSelectionPlaceholder
            }
        }
    }

    private var noSelectionPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            HelmBrandIconView(size: 48)
            Text("No Release Selected")
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
            Text("Select a Helm release on the left to inspect its values, rendered manifest, and revision history.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailHeader(_ release: HelmReleaseItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HelmBrandIconView(size: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(release.name)
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(.primary)

                    CTXCopyIconButton(value: release.name)

                    statusChip(release.status)
                }
                Text("Namespace: \(release.namespace)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Metadata Chips
            HStack(spacing: 8) {
                if release.chart != KubernetesGitOpsService.unknownValue {
                    metadataBadge(title: "Chart", value: release.chart, systemImage: "shippingbox.fill")
                }
                if release.appVersion != KubernetesGitOpsService.unknownValue && !release.appVersion.isEmpty {
                    metadataBadge(title: "App", value: release.appVersion, systemImage: "tag.fill")
                }
                metadataBadge(title: "Revision", value: "\(release.revision)", systemImage: "arrow.counterclockwise")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func metadataBadge(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
            Text("\(title): \(value)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Native Segmented Tab Bar & Controls

    private var detailTabBar: some View {
        HStack(spacing: 12) {
            // Unified Segmented Pill Tab Bar (Icon + Text combined in a single clickable tab)
            HStack(spacing: 2) {
                ForEach(ClusterWorkspaceViewModel.HelmDetailTab.allCases) { tab in
                    let isSelected = viewModel.helmDetailTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.setHelmTab(tab)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tabIcon(tab))
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? Color.primary.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 0.75)
            }
            .fixedSize()

            Spacer()

            // Values Tab: User vs All Computed toggle (Pill switcher)
            if viewModel.helmDetailTab == .values {
                HStack(spacing: 2) {
                    Button {
                        if viewModel.helmIncludeAllValues {
                            viewModel.toggleHelmAllValues()
                        }
                    } label: {
                        Text("User Values")
                            .font(.system(size: 11, weight: !viewModel.helmIncludeAllValues ? .semibold : .regular))
                            .foregroundStyle(!viewModel.helmIncludeAllValues ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
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
                            .font(.system(size: 11, weight: viewModel.helmIncludeAllValues ? .semibold : .regular))
                            .foregroundStyle(viewModel.helmIncludeAllValues ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
    private func detailTabContent(_ release: HelmReleaseItem) -> some View {
        if viewModel.isLoadingHelmDetail || viewModel.isRollingBackHelm {
            CTXLoadingStateView(
                title: viewModel.isRollingBackHelm ? "Rolling Back Release..." : "Loading \(viewModel.helmDetailTab.rawValue)...",
                message: viewModel.isRollingBackHelm ? "Running 'helm rollback'..." : "Querying Helm release...",
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
                historyTabView(release)
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

                    // Native CTX Copy Icon Button with spring checkmark animation
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

                    // Native CTX Copy Icon Button (copies filtered kind or full manifest)
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

    // MARK: - History Tab View (Pixel-Perfect Column Alignment + Rollback Action)

    private enum HistoryColumns {
        static let revision: CGFloat = 100
        static let status: CGFloat = 110
        static let chart: CGFloat = 170
        static let appVersion: CGFloat = 100
        static let updated: CGFloat = 115
        static let actions: CGFloat = 90
    }

    private func historyTabView(_ release: HelmReleaseItem) -> some View {
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
                    // History Table Header (Exact Matching Column Widths)
                    HStack(spacing: 12) {
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
                            .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                        Text("ACTION")
                            .frame(width: HistoryColumns.actions, alignment: .trailing)
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.04))

                    Divider().opacity(0.4)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.helmHistory) { item in
                                historyRow(item, isActive: item.revision == release.revision)
                                Divider().opacity(0.2)
                            }
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ item: HelmRevisionItem, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            // Revision Column: rev + CURRENT pill on a single line with zero vertical wrapping
            HStack(spacing: 6) {
                Text("\(item.revision)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                if isActive {
                    Text("CURRENT")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
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
            Text(item.chart)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: HistoryColumns.chart, alignment: .leading)

            // App Version Column
            Text(item.appVersion.isEmpty ? "-" : item.appVersion)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: HistoryColumns.appVersion, alignment: .leading)

            // Updated Column
            Text(item.updated)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: HistoryColumns.updated, alignment: .leading)

            // Description Column
            Text(item.description.isEmpty ? "-" : item.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)

            // Actions Column: Rollback button for non-active revisions
            HStack {
                Spacer()
                if isActive {
                    Text("Active")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        rollbackCandidate = item
                        isShowingRollbackAlert = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9, weight: .bold))
                            Text("Rollback")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: HistoryColumns.actions, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(isActive ? Color.accentColor.opacity(0.06) : Color.clear)
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

        // If kind filter is set, find the sub-blocks that belong to that kind
        let linesToDisplay: [CodeLineItem] = buildDisplayLines(rawLines: rawLines, kindFilter: kindFilter, searchQuery: codeSearchText)

        let gutterWidth: CGFloat = linesToDisplay.count > 999 ? 44 : 34

        return GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(linesToDisplay) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            // Fixed-width line number gutter
                            Text("\(item.number)")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.secondary.opacity(0.45))
                                .frame(width: gutterWidth, alignment: .trailing)

                            // Code line with strict lineLimit and fixedSize to PREVENT word-squishing!
                            Text(item.text.isEmpty ? " " : item.text)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(codeLineColor(item.text))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 18, alignment: .leading)
                        .background(
                            item.isMatch
                                ? Color.yellow.opacity(0.22)
                                : Color.clear
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minWidth: proxy.size.width, maxWidth: .infinity, alignment: .topLeading)
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
        let image: NSImage? = {
            if let bundle = Bundle.safeModule,
               let url = bundle.url(forResource: "helm", withExtension: "svg"),
               let img = NSImage(contentsOf: url) {
                return img
            }
            if let directImg = NSImage(contentsOfFile: "Sources/CTX/Resources/helm.svg") {
                return directImg
            }
            return nil
        }()

        if let nsImage = image {
            let _ = { nsImage.size = NSSize(width: size, height: size) }()
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            // Resolution-independent CNCF Helm Nautical Wheel Vector
            KubernetesIconView(
                icon: .helm,
                size: size,
                tint: Color(hex: "2496ED"),
                filledBackground: false
            )
            .frame(width: size, height: size)
        }
    }
}
