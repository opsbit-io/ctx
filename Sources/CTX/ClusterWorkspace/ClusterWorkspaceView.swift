import CTXCore
import SwiftUI

struct ClusterWorkspaceScene: View {
    @ObservedObject var store: ProfileStore
    let contextID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var activeContextID: String?

    private var effectiveContextID: String {
        activeContextID ?? contextID
    }

    private var context: KubernetesContextProfile? {
        if !effectiveContextID.isEmpty {
            if let found = store.kubernetesContexts.first(where: { $0.id == effectiveContextID || $0.contextName == effectiveContextID }) {
                return found
            }
        }
        if !contextID.isEmpty {
            if let found = store.kubernetesContexts.first(where: { $0.id == contextID || $0.contextName == contextID }) {
                return found
            }
        }
        return nil
    }

    private var profile: CloudProfile? {
        guard let context else { return nil }
        return store.profiles.first { $0.provider == .kubernetes && $0.name == context.contextName }
    }

    var body: some View {
        if let context {
            ClusterWorkspaceContextHost(
                store: store,
                context: context,
                onSelectCluster: { newContext in
                    activeContextID = newContext.id
                }
            )
            .id(context.id)
            .onChange(of: profile == nil) { _, isDeleted in
                if isDeleted {
                    dismissWindow()
                }
            }
            .onChange(of: profile?.status) { _, newStatus in
                if newStatus == .disconnecting {
                    dismissWindow()
                }
            }
        } else {
            ClusterWorkspaceNewTabLauncher(
                store: store,
                onSelectCluster: { selected in
                    activeContextID = selected.id
                }
            )
            .ctxNativeToolbarWindow(title: "New Cluster Tab")
        }
    }

    private func dismissWindow() {
        dismiss()
        DispatchQueue.main.async {
            for window in NSApp.windows {
                if window.title == effectiveContextID || window.title.contains(effectiveContextID) {
                    window.close()
                }
            }
        }
    }
}

/// Owns presentation state for exactly one workspace window and context.
/// Resource caches may deduplicate reads underneath, but tabs, namespace, selection,
/// cancellation and loading state must never leak into another window.
private struct ClusterWorkspaceContextHost: View {
    @ObservedObject var store: ProfileStore
    let context: KubernetesContextProfile
    let onSelectCluster: (KubernetesContextProfile) -> Void
    @StateObject private var viewModel: ClusterWorkspaceViewModel

    init(
        store: ProfileStore,
        context: KubernetesContextProfile,
        onSelectCluster: @escaping (KubernetesContextProfile) -> Void
    ) {
        self.store = store
        self.context = context
        self.onSelectCluster = onSelectCluster
        _viewModel = StateObject(wrappedValue: ClusterWorkspaceViewModel(context: context))
    }

    var body: some View {
        ClusterWorkspaceView(
            store: store,
            viewModel: viewModel,
            onSelectCluster: onSelectCluster
        )
        .onAppear {
            viewModel.onStatusCheckFailed = { contextName, reason in
                store.markKubernetesContextNeedsLogin(contextName: contextName, reason: reason)
            }
        }
    }
}

private struct ClusterSearchRequest: Identifiable {
    let id = UUID()
    let query: String
}

struct ClusterWorkspaceView: View {
    let store: ProfileStore
    let onSelectCluster: ((KubernetesContextProfile) -> Void)?
    @ObservedObject var viewModel: ClusterWorkspaceViewModel
    @State private var searchRequest: ClusterSearchRequest?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var clusterSearchState = ToolbarSearchState()

    init(
        store: ProfileStore,
        viewModel: ClusterWorkspaceViewModel,
        onSelectCluster: ((KubernetesContextProfile) -> Void)? = nil
    ) {
        self.store = store
        self.viewModel = viewModel
        self.onSelectCluster = onSelectCluster
    }

    @AppStorage(AppAppearance.storageKey) private var appAppearanceRaw: String = AppAppearance.dark.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRaw) ?? .dark
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ClusterWorkspaceSidebar(viewModel: viewModel)
                .background(colorScheme == .light ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.black.opacity(0.25))
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 310)
        } detail: {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    ClusterWorkspaceHeader(
                        viewModel: viewModel,
                        store: store,
                        onSelectCluster: onSelectCluster,
                        onBackToCTX: backToCTX
                    )
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                    Divider()
                        .opacity(0.5)

                    ClusterWorkspaceContent(viewModel: viewModel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(colorScheme == .light ? Color(NSColor.windowBackgroundColor) : Color(white: 0.12).opacity(0.65))
                .environment(\.workspaceContentWidth, proxy.size.width)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                CTXToolbarSearchControl(
                    prompt: "Search Cluster",
                    state: $clusterSearchState,
                    onSubmit: presentClusterSearch
                )

                Menu {
                    Button {
                        openWindow(id: "cluster-workspace", value: "")
                    } label: {
                        Label("New Cluster Workspace", systemImage: "macwindow.badge.plus")
                    }

                    Button {
                        viewModel.selectedSection = .portForward
                    } label: {
                        Label("New Port Forward", systemImage: "arrow.left.arrow.right")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuIndicator(.hidden)
                .help("Open a Workspace or start a Port Forward")
                .accessibilityLabel("Cluster Workspace actions")
            }
        }
        .background(VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow))
        .ctxNativeToolbarWindow(title: viewModel.title)
        .preferredColorScheme(currentAppearance.colorScheme)
        .frame(minWidth: 680, minHeight: 480)
        .task(id: viewModel.context.id) {
            await viewModel.refreshOverviewIfNeeded()
            viewModel.prefetchWorkspaceResources()

            let ctxID = viewModel.context.id
            let ctxName = viewModel.context.contextName
            if let target = store.pendingClusterDeepLink[ctxID] ?? store.pendingClusterDeepLink[ctxName] {
                store.pendingClusterDeepLink.removeValue(forKey: ctxID)
                store.pendingClusterDeepLink.removeValue(forKey: ctxName)
                let kind = KubernetesResourceKind(rawValue: target.resourceKind)
                    ?? KubernetesResourceKind.allCases.first(where: { $0.title.lowercased() == target.resourceKind.lowercased() })
                    ?? .pods
                await viewModel.navigateToResource(
                    kind: kind,
                    name: target.resourceName,
                    namespace: target.namespace,
                    tab: .diagnostics
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ctxDeepLinkToResource)) { notif in
            guard let ctxID = notif.userInfo?["context_id"] as? String,
                  ctxID == viewModel.context.id || ctxID == viewModel.context.contextName else { return }
            guard let kindStr = notif.userInfo?["resource_kind"] as? String,
                  let kind = KubernetesResourceKind(rawValue: kindStr) ?? KubernetesResourceKind.allCases.first(where: { $0.title.lowercased() == kindStr.lowercased() }),
                  let name = notif.userInfo?["resource_name"] as? String else { return }
            let ns = notif.userInfo?["namespace"] as? String
            Task {
                await viewModel.navigateToResource(kind: kind, name: name, namespace: ns, tab: .diagnostics)
            }
        }
        .onChange(of: viewModel.selectedSection) { _, newValue in
            if newValue == .overview {
                Task { await viewModel.refreshOverviewIfNeeded() }
            }
        }
        .onDisappear {
            viewModel.cancelRefresh()
        }
        .sheet(item: $searchRequest) { request in
            ClusterCommandPaletteModal(viewModel: viewModel, initialQuery: request.query)
        }
        .overlay {
            if viewModel.isQuickLookActive, let row = viewModel.quickLookResource, let section = viewModel.quickLookSection {
                CTXQuickLookOverlay(viewModel: viewModel, row: row, section: section)
            }
        }
        .background {
            HStack {
                // Command Palette (Spotlight-style ⌘K)
                Button("") { clusterSearchState.activate() }
                    .keyboardShortcut("k", modifiers: .command)

                Button("") { clusterSearchState.activate() }
                    .keyboardShortcut("f", modifiers: .command)

                // Spacebar Quick Look — disabled while the YAML editor is open so a
                // literal space typed into a manifest is never eaten by this instead.
                Button("") { viewModel.toggleQuickLook() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(viewModel.isEditingYAML)

                // Bypass Cache & Reload (⌘R)
                Button("") { viewModel.refreshCurrentScreen() }
                    .keyboardShortcut("r", modifiers: .command)

                // New Tab (⌘T)
                Button("") { openWindow(id: "cluster-workspace", value: "") }
                    .keyboardShortcut("t", modifiers: .command)

                // New Window (⌘N)
                Button("") { openWindow(id: "cluster-workspace", value: "") }
                    .keyboardShortcut("n", modifiers: .command)

                // Section Navigation (⌘1 to ⌘8)
                Button("") { viewModel.selectedSection = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { viewModel.selectedSection = .topology }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { viewModel.selectedSection = .workloads }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { viewModel.selectedSection = .pods }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { viewModel.selectedSection = .services }
                    .keyboardShortcut("5", modifiers: .command)
                Button("") { viewModel.selectedSection = .logs }
                    .keyboardShortcut("6", modifiers: .command)
                Button("") { viewModel.selectedSection = .portForward }
                    .keyboardShortcut("7", modifiers: .command)
                Button("") { viewModel.selectedSection = .issues }
                    .keyboardShortcut("8", modifiers: .command)

                // Direct Resource Shortcuts (⌘L for Logs, ⌘Y for YAML)
                Button("") {
                    if let row = viewModel.activeSelectedResource {
                        viewModel.openInspector(for: row, in: viewModel.selectedSection, tab: .logs)
                    }
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("") {
                    if let row = viewModel.activeSelectedResource {
                        viewModel.openInspector(for: row, in: viewModel.selectedSection, tab: .yaml)
                    }
                }
                .keyboardShortcut("y", modifiers: .command)

                Button("") {
                    if let row = viewModel.activeSelectedResource, row.cells["Ports"] != nil || row.cells["Port(s)"] != nil {
                        viewModel.selectedSection = .portForward
                    }
                }
                .keyboardShortcut("p", modifiers: .command)

                // Dismiss QuickLook / Inspector
                Button("") {
                    if viewModel.isQuickLookActive {
                        viewModel.dismissQuickLook()
                    } else if viewModel.presentation != nil {
                        viewModel.dismissPresentation()
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    private func backToCTX() {
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "CTX" }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentClusterSearch(_ query: String) {
        searchRequest = ClusterSearchRequest(query: query)
    }
}

struct ClusterWorkspaceHeader: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel
    let store: ProfileStore
    var onSelectCluster: ((KubernetesContextProfile) -> Void)? = nil
    var onBackToCTX: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            horizontalHeader
        }
    }

    @ViewBuilder
    private var navigationControl: some View {
        if let onBackToCTX {
            Button(action: onBackToCTX) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Profiles")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .help("Back to CTX Profiles window")
        }
    }

    private var clusterProfileProvider: CloudProvider {
        KubernetesProfileAdapter.cloudProfile(from: viewModel.context).provider
    }

    private var clusterIcon: some View {
        ProviderIcon(provider: clusterProfileProvider, size: 26, fallbackTint: Color.accentColor)
            .frame(width: 46, height: 46)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .fixedSize()
    }

    private var horizontalHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            navigationControl
            clusterIcon
            titleBlock
                .frame(minWidth: 0, alignment: .leading)
            Spacer(minLength: 8)
            ClusterWorkspaceHeaderActions(viewModel: viewModel, store: store)
                .layoutPriority(1)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let onSelectCluster {
                ClusterWorkspaceClusterSelector(
                    store: store,
                    currentContext: viewModel.context,
                    onSelectCluster: onSelectCluster,
                    style: .standard
                )
            } else {
                HStack(spacing: 9) {
                    Text(viewModel.title)
                        .font(.system(.title2, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(viewModel.fullContextName)
                        .layoutPriority(1)
                    CTXEnvironmentBadge(environment: viewModel.context.environmentType)
                        .fixedSize()
                }
            }

            HStack(spacing: 8) {
                Text(viewModel.clusterName)
                    .font(.system(.footnote, design: .monospaced, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.fullContextName, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Copy full context ARN: \(viewModel.fullContextName)")
            }
            .help(viewModel.fullContextName)

            HStack(spacing: 8) {
                ClusterNamespaceSelector(viewModel: viewModel)
                if let expiry = AWSSessionExpirationService().sessionExpiry(for: KubernetesProfileAdapter.cloudProfile(from: viewModel.context)) {
                    let remaining = expiry.timeIntervalSinceNow
                    if remaining > 0 {
                        let hours = Int(remaining) / 3600
                        let mins = (Int(remaining) % 3600) / 60
                        CTXStatusBadge(title: "Session: \(hours)h \(mins)m", systemImage: "clock.badge.checkmark", tint: remaining < 1800 ? .orange : .green)
                            .help("Cloud STS Session valid until \(expiry.formatted(.dateTime.hour().minute()))")
                    }
                }
            }
        }
    }

}

struct ClusterWorkspaceView_Previews: PreviewProvider {
    static var previews: some View {
        let store = ProfileStore(startsBackgroundServices: false)
        let vm = ClusterWorkspaceViewModel(context: .previewProduction)
        ClusterWorkspaceView(store: store, viewModel: vm)
    }
}
