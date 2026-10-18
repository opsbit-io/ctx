import CTXCore
import SwiftUI

/// Standalone Apple-grade Debug Console for Container Logs (`ClusterLogsView`).
///
/// Features a responsive Master-Detail split (collapsible left Pod Browser + right Live Terminal Console),
/// automatic initial Pod selection so the screen is never an empty box, status filtering (`All / Issues / Running`),
/// Container picker, Tail count selector, and 1-click Pod Inspector navigation.
struct ClusterLogsView: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel

    enum PodFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case issues = "Attention"
        case running = "Running"
        var id: String { rawValue }
    }

    @State private var podSearchText = ""
    @State private var podFilter: PodFilter = .all
    @State private var isPodSidebarCollapsed = false

    private static let tailOptions = [100, 500, 1000]

    private var podsList: KubernetesResourceList? {
        viewModel.resourceList(for: .pods)
    }

    private var pods: [KubernetesResourceRow] {
        podsList?.rows ?? []
    }

    private var sortedPods: [KubernetesResourceRow] {
        PodLogSelection.sortedForPicker(pods)
    }

    private var warningPodsCount: Int {
        pods.filter { PodLogSelection.rank(for: $0) == .warning }.count
    }

    private var filteredPods: [KubernetesResourceRow] {
        sortedPods.filter { row in
            switch podFilter {
            case .all:
                break
            case .issues:
                guard PodLogSelection.rank(for: row) == .warning || PodLogSelection.rank(for: row) == .pending else { return false }
            case .running:
                guard PodLogSelection.rank(for: row) == .runningReady else { return false }
            }
            guard !podSearchText.isEmpty else { return true }
            let q = podSearchText.lowercased()
            return row.name.lowercased().contains(q)
                || (row.namespace ?? "").lowercased().contains(q)
                || (row.cells["Workload"] ?? "").lowercased().contains(q)
                || (row.cells["Status"] ?? "").lowercased().contains(q)
        }
    }

    private var isAllNamespaces: Bool {
        viewModel.selectedNamespace == .allNamespaces
    }

    private var selectedPodRow: KubernetesResourceRow? {
        pods.first { $0.id == viewModel.selectedLogPodID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.16), value: viewModel.isLoadingLogs)
        .animation(.easeInOut(duration: 0.16), value: viewModel.selectedLogPodID)
        .onAppear {
            if podsList == nil {
                viewModel.loadPodsForLogs()
            } else {
                autoSelectFirstRelevantPod(from: pods)
            }
        }
        .onChange(of: pods) { _, newPods in
            autoSelectFirstRelevantPod(from: newPods)
        }
    }

    /// Automatically selects the most relevant pod (prioritizing warning/crashing pods first, then running pods)
    /// so the user immediately sees live container logs without having to hunt for a dropdown.
    private func autoSelectFirstRelevantPod(from rows: [KubernetesResourceRow]) {
        guard !rows.isEmpty else { return }
        if let currentID = viewModel.selectedLogPodID, rows.contains(where: { $0.id == currentID }) {
            return
        }
        let sorted = PodLogSelection.sortedForPicker(rows)
        if let warningPod = sorted.first(where: { PodLogSelection.rank(for: $0) == .warning }) {
            viewModel.selectLogPod(warningPod)
        } else if let firstPod = sorted.first {
            viewModel.selectLogPod(firstPod)
        }
    }

    // MARK: - Single Unified Header Bar

    private var headerBar: some View {
        CTXUnifiedHeaderBar(
            title: "Container Logs",
            systemImage: "terminal.fill",
            iconTint: .cyan,
            countBadge: pods.count,
            countTint: .cyan,
            isSidebarCollapsed: $isPodSidebarCollapsed,
            sidebarHelp: isPodSidebarCollapsed ? "Show Pods List" : "Hide Pods List"
        ) {
            EmptyView()
        } trailingControls: {
            if isPodSidebarCollapsed && !pods.isEmpty {
                CTXPodPicker(
                    pods: pods,
                    selectedPodID: viewModel.selectedLogPodID,
                    showsNamespaceColumn: isAllNamespaces,
                    onSelect: { viewModel.selectLogPod($0) }
                )
            }

            if viewModel.logContainers.count > 1 {
                Picker("Container", selection: containerBinding) {
                    ForEach(viewModel.logContainers, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)
            }

            CTXLogsTailSelector(options: Self.tailOptions, selection: tailBinding)

            if let pod = selectedPodRow {
                Button {
                    viewModel.selectResource(pod, in: .pods)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Inspect Pod")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color.secondary.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open Pod Inspector for \(pod.name)")
            }

            if let text = viewModel.logsResult?.text, !text.isEmpty {
                CTXCopyIconButton(value: text)
            }
        }
    }

    // MARK: - Split Master-Detail Content

    @ViewBuilder
    private var content: some View {
        if podsList == nil {
            CTXGlassPanel {
                CTXLoadingStateView(
                    title: "Loading Pods",
                    message: "Fetching pods in '\(viewModel.namespace)'...",
                    centered: true
                )
            }
        } else if let list = podsList, list.status != .reachable {
            ResourceIssuePanel(
                section: .pods,
                list: list,
                retry: { viewModel.loadPodsForLogs() }
            )
        } else if pods.isEmpty {
            CTXGlassPanel {
                CTXEmptyStateView(
                    title: "No Pods in \(viewModel.namespace)",
                    message: "There are no pods running in this namespace to stream logs from.",
                    systemImage: "cube.transparent"
                )
            }
        } else {
            GeometryReader { geo in
                let showSidebar = !isPodSidebarCollapsed && geo.size.width >= 760
                let sidebarWidth = min(max(geo.size.width * 0.27, 240), 320)

                HStack(alignment: .top, spacing: 12) {
                    if showSidebar {
                        podBrowserSidebar
                            .frame(width: sidebarWidth)
                            .frame(maxHeight: .infinity)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    logConsoleDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Left Pod Browser Sidebar

    private var podBrowserSidebar: some View {
        CTXGlassPanel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PODS (\(filteredPods.count))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                        Spacer()
                        if warningPodsCount > 0 {
                            Text("\(warningPodsCount) issue\(warningPodsCount == 1 ? "" : "s")")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        }
                    }

                    Picker("Filter", selection: $podFilter) {
                        ForEach(PodFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    CTXSearchField(placeholder: "Filter pods...", text: $podSearchText)
                }
                .padding(10)

                Divider().opacity(0.5)

                if filteredPods.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.tertiary)
                        Text("No matching pods")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 5) {
                            ForEach(filteredPods) { row in
                                podBrowserRow(row)
                            }
                        }
                        .padding(8)
                    }
                }
            }
        }
    }

    private func podBrowserRow(_ row: KubernetesResourceRow) -> some View {
        let isSelected = row.id == viewModel.selectedLogPodID
        let tint = statusTint(for: row)
        let status = row.cells["Status"] ?? "—"
        let ready = row.cells["Ready"] ?? ""
        let restarts = row.cells["Restarts"] ?? "—"

        return Button {
            viewModel.selectLogPod(row)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)

                    Text(row.name)
                        .font(.system(size: 11.5, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 2)
                }

                HStack(spacing: 6) {
                    if isAllNamespaces, let ns = row.namespace, !ns.isEmpty {
                        Text(ns)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(status)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if !ready.isEmpty {
                        Text(ready)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if restarts != "0" && !restarts.isEmpty {
                        Text("↻\(restarts)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.025))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.05), lineWidth: isSelected ? 1.2 : 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Log Console Detail

    @ViewBuilder
    private var logConsoleDetail: some View {
        if viewModel.selectedLogPodID == nil {
            CTXGlassPanel {
                CTXEmptyStateView(
                    title: "Select a Pod",
                    message: "Choose a pod from the sidebar to stream its container logs.",
                    systemImage: "terminal"
                )
            }
        } else if viewModel.isLoadingLogs && viewModel.logsResult == nil {
            CTXGlassPanel {
                CTXLoadingStateView(
                    title: "Streaming Container Logs",
                    message: "Fetching recent logs for \(selectedPodRow?.name ?? "pod")...",
                    centered: true
                )
            }
        } else if let result = viewModel.logsResult {
            switch result.status {
            case .reachable:
                let text = result.text ?? ""
                if text.isEmpty {
                    CTXGlassPanel {
                        CTXEmptyStateView(
                            title: "No Log Output",
                            message: "The container has not written any lines to stdout/stderr yet.",
                            systemImage: "text.page.slash"
                        )
                    }
                } else {
                    CTXGlassPanel(padding: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            if let pod = selectedPodRow {
                                activePodBanner(pod)
                                Divider().opacity(0.55)
                            }
                            CTXLogsViewer(rawText: text, tailLines: viewModel.logTailLines)
                        }
                    }
                }
            default:
                CTXLogsIssuePanel(result: result, retry: { viewModel.reloadLogs() })
            }
        }
    }

    private func activePodBanner(_ pod: KubernetesResourceRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "cube.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.cyan)

            Text(pod.name)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let status = pod.cells["Status"], !status.isEmpty {
                CTXSemanticPill(
                    text: status,
                    tint: statusTint(for: pod)
                )
            }

            if let ns = pod.namespace, !ns.isEmpty {
                Text(ns)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            if let container = viewModel.selectedLogContainer ?? viewModel.logContainers.first {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 9.5))
                    Text(container)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.cyan.opacity(0.14), in: Capsule())
                .foregroundStyle(.cyan)
            }

            Spacer()

            if let node = pod.cells["Node"], !node.isEmpty {
                Text("Node: \(node)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    private func statusTint(for row: KubernetesResourceRow) -> Color {
        switch PodLogSelection.rank(for: row) {
        case .runningReady: return .green
        case .warning: return .red
        case .pending: return .orange
        case .completed: return .secondary
        }
    }

    private var containerBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedLogContainer ?? viewModel.logContainers.first ?? "" },
            set: { viewModel.selectLogContainer($0) }
        )
    }

    private var tailBinding: Binding<Int> {
        Binding(
            get: { viewModel.logTailLines },
            set: { viewModel.setLogTailLines($0) }
        )
    }
}
