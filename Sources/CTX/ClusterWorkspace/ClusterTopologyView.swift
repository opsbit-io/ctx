import CTXCore
import SwiftUI

struct ClusterTopologyView: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel
    @State private var scale: CGFloat = 1
    @State private var command: TopologyMapCommand?
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedNodeID: String?
    @State private var needsAttentionOnly = false
    @State private var showsInactive = false
    @State private var selectedCategory: TopologyNodeCategory? = nil

    private var projection: TopologyProjection? { viewModel.topologyProjection }

    private var filter: TopologyMapFilter {
        TopologyMapFilter(
            searchText: viewModel.topologySelectorText,
            includesInactive: showsInactive,
            needsAttentionOnly: needsAttentionOnly,
            category: selectedCategory
        )
    }

    var body: some View {
        let snapshot = TopologyMapSnapshot(
            projected: viewModel.topologyGraph,
            projection: projection,
            filter: filter
        )

        return VStack(spacing: 0) {
            TopologyToolbarView(
                searchText: $searchText,
                needsAttentionOnly: $needsAttentionOnly,
                showsInactive: $showsInactive,
                selectedCategory: $selectedCategory,
                scale: scale,
                counts: TopologyCountSummary(snapshot),
                command: $command,
                categoryCounts: categoryCounts(in: viewModel.topologyGraph)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            TopologyResponsiveInspectorLayout(
                isPresented: selectedNode(in: snapshot) != nil,
                canvas: {
                    canvas(snapshot)
                },
                inspector: {
                    inspector(snapshot)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            searchText = viewModel.topologySelectorText
            viewModel.loadTopologyResources()
        }
        .onChange(of: searchText) { _, value in
            scheduleSelectorUpdate(value)
        }
        .onChange(of: viewModel.topologyScopeID) { _, _ in
            searchTask?.cancel()
            searchTask = nil
            searchText = ""
            selectedNodeID = nil
        }
        .onChange(of: viewModel.topologySelectorText) { _, value in
            guard value != searchText else { return }
            searchTask?.cancel()
            searchText = value
            selectedNodeID = nil
        }
        .onChange(of: snapshot.graph.nodes.map(\.id)) { _, ids in
            if let selectedNodeID, !ids.contains(selectedNodeID) {
                self.selectedNodeID = nil
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onExitCommand {
            selectedNodeID = nil
        }
        .background {
            zoomShortcuts
        }
    }

    private var zoomShortcuts: some View {
        HStack {
            Button("") { command = .zoomIn }
                .keyboardShortcut("+", modifiers: .command)
            Button("") { command = .zoomOut }
                .keyboardShortcut("-", modifiers: .command)
            Button("") { command = .fit }
                .keyboardShortcut("0", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func canvas(_ snapshot: TopologyMapSnapshot) -> some View {
        Group {
            switch snapshot.vacancy {
            case .none:
                ClusterDAGGraphView(
                    graph: snapshot.graph,
                    groupsByNodeID: projection?.groupsByNodeID ?? [:],
                    onExpandGroup: { viewModel.expandTopologyGroup($0) },
                    scale: $scale,
                    command: $command,
                    selectedNodeID: $selectedNodeID
                )
            case .awaitingProjection:
                ResourceSkeletonView(
                    title: "Bringing \(snapshot.eligibleCount) matching object\(snapshot.eligibleCount == 1 ? "" : "s") into view"
                )
                .padding(22)
            case .noSearchMatch:
                CTXEmptyStateView(
                    title: "No match for “\(viewModel.topologySelectorText)”",
                    message: "Try another object name, or clear the lineage search.",
                    systemImage: "magnifyingglass"
                )
            case .noAttentionNeeded:
                CTXEmptyStateView(
                    title: "No objects need attention",
                    message: "Clear the filter to see the full active map.",
                    systemImage: "checkmark.circle"
                )
            case .allInactive:
                CTXEmptyStateView(
                    title: "All objects are inactive",
                    message: "Turn on Show inactive to include completed or scaled-to-zero objects.",
                    systemImage: "moon.zzz"
                )
            case .noObjects:
                if viewModel.isTopologyPending {
                    ResourceSkeletonView(title: "Building the service map")
                        .padding(22)
                } else {
                    CTXEmptyStateView(
                        title: "Nothing to map",
                        message: "The map appears once Services, Workloads and Pods have loaded.",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
    }

    @ViewBuilder
    private func inspector(_ snapshot: TopologyMapSnapshot) -> some View {
        if let inspected = selectedNode(in: snapshot) {
            TopologyNodeInspectorView(
                node: inspected,
                graph: snapshot.graph,
                group: projection?.groupsByNodeID[inspected.id],
                canCollapse: viewModel.topologyExpansionState.batchCount(for: inspected.id) > 0,
                onSelect: { selectedNodeID = $0 },
                onOpenInspector: { openInspector(inspected) },
                onPortForward: inspected.kind == .service ? { openPortForward(inspected) } : nil,
                onShowPods: projection?.groupsByNodeID[inspected.id].map { group in
                    { showPods(group) }
                },
                onExpand: { viewModel.expandTopologyGroup(inspected.id) },
                onCollapse: { viewModel.collapseTopologyGroup(inspected.id) },
                onResetExpansion: viewModel.topologyExpansionState.batchesByGroupID.isEmpty
                    ? nil
                    : { viewModel.resetTopologyExpansion() },
                onClose: { selectedNodeID = nil }
            )
        }
    }

    private func selectedNode(in snapshot: TopologyMapSnapshot) -> TopologyGraphNode? {
        selectedNodeID.flatMap(snapshot.graph.node)
    }

    private func openInspector(_ node: TopologyGraphNode) {
        guard let section = node.kind.workspaceSection else { return }
        viewModel.selectResource(node.row, in: section)
    }

    private func openPortForward(_ node: TopologyGraphNode) {
        viewModel.selectPortForwardService(node.row)
        viewModel.selectedSection = .portForward
    }

    private func scheduleSelectorUpdate(_ value: String) {
        searchTask?.cancel()
        guard value != viewModel.topologySelectorText else { return }
        let scope = viewModel.topologyScopeID
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled,
                  scope == viewModel.topologyScopeID,
                  value != viewModel.topologySelectorText else { return }
            viewModel.setTopologySelector(value)
        }
    }

    
    private func categoryCounts(in graph: ClusterTopologyGraph) -> [TopologyNodeCategory: Int] {
        var counts: [TopologyNodeCategory: Int] = [:]
        for node in graph.nodes {
            counts[node.category, default: 0] += 1
        }
        return counts
    }

    private func showPods(_ group: TopologyProjectedGroup) {
        let rowIDs = Set(group.memberNodeIDs.compactMap { id -> String? in
            guard id.hasPrefix("pod/") else { return nil }
            return String(id.dropFirst("pod/".count))
        })
        guard !rowIDs.isEmpty else { return }
        viewModel.resourceFocus = ResourceFocus(
            section: .pods,
            title: "\(group.hiddenCount) pods represented on the map",
            ids: rowIDs
        )
        viewModel.selectedSection = .pods
    }
}

private extension TopologyGraphNodeKind {
    var workspaceSection: ClusterWorkspaceSection? {
        switch self {
        case .ingress: .ingress
        case .service: .services
        case .workload, .deployment, .statefulSet, .daemonSet, .replicaSet, .job: .workloads
        case .cronJob: .cronjobs
        case .pod: .pods
        case .pvc, .pv, .storageClass: .storage
        case .configMap: .configMaps
        case .secret: .secrets
        case .hpa: .hpa
        case .networkPolicy: .ingress
        case .serviceAccount, .role, .clusterRole, .roleBinding: nil
        case .podGroup, .terminalGroup, .overflow: nil
        }
    }
}
