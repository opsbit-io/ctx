import CTXCore
import SwiftUI

/// Apple HIG native popover & menu for viewing active Kubernetes connections,
/// switching clusters within the current workspace, or opening clusters in a new window/tab.
struct ClusterWorkspaceClusterSelector: View {
    enum Style {
        case standard
        case compact
    }

    @ObservedObject var store: ProfileStore
    let currentContext: KubernetesContextProfile
    let onSelectCluster: (KubernetesContextProfile) -> Void
    var onOpenInNewWindow: ((KubernetesContextProfile) -> Void)? = nil
    var style: Style = .standard

    @State private var isPresented = false
    @State private var searchQuery = ""
    @Environment(\.openWindow) private var openWindow

    private var activeKubernetesProfiles: [CloudProfile] {
        store.connectedProfiles.filter { $0.provider == .kubernetes }
    }

    private var activeContexts: [KubernetesContextProfile] {
        var results: [KubernetesContextProfile] = []
        var seenIDs = Set<String>()

        for profile in activeKubernetesProfiles {
            if let ctx = store.kubernetesContexts.first(where: { $0.contextName == profile.name || $0.id == profile.id }) {
                if !seenIDs.contains(ctx.id) {
                    seenIDs.insert(ctx.id)
                    results.append(ctx)
                }
            } else {
                let fallback = KubernetesContextProfile(
                    contextName: profile.name,
                    clusterName: profile.name,
                    kubeconfigPath: "",
                    providerType: .unknown
                )
                if !seenIDs.contains(fallback.id) {
                    seenIDs.insert(fallback.id)
                    results.append(fallback)
                }
            }
        }

        // Always include the current context if somehow not in active profiles
        if !seenIDs.contains(currentContext.id) {
            results.insert(currentContext, at: 0)
        }

        return results
    }

    private var filteredActiveContexts: [KubernetesContextProfile] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return activeContexts }
        return activeContexts.filter {
            $0.contextName.lowercased().contains(q)
                || $0.cleanClusterName.lowercased().contains(q)
                || $0.clusterName.lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if style == .compact {
                compactTrigger
            } else {
                standardTrigger
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: style == .compact ? .trailing : .bottom) {
            popoverContent
                .frame(width: 480)
        }
    }

    private var standardTrigger: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(currentContext.cleanClusterName)
                        .font(.system(.title2, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                CTXEnvironmentBadge(environment: currentContext.environmentType)
                    .fixedSize()

                if activeContexts.count > 1 {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("\(activeContexts.count) Active")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12), in: Capsule())
                    .overlay {
                        Capsule().stroke(Color.green.opacity(0.25), lineWidth: 0.75)
                    }
                    .help("\(activeContexts.count) Kubernetes clusters currently connected")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var compactTrigger: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                Text("\(activeContexts.count) Active")
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.12), in: Capsule())
            .overlay {
                Capsule().stroke(Color.green.opacity(0.25), lineWidth: 0.75)
            }
            .help("Switch between \(activeContexts.count) connected clusters")
        }
        .buttonStyle(.plain)
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Connected Clusters", systemImage: "server.rack")
                        .font(.system(.subheadline, weight: .bold))
                    Spacer()
                    Text("\(activeContexts.count) Connected")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                        .overlay {
                            Capsule().stroke(Color.green.opacity(0.25), lineWidth: 0.75)
                        }
                }

                if activeContexts.count > 4 {
                    CTXSearchField(placeholder: "Filter connected clusters...", text: $searchQuery)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)

            Divider().opacity(0.6)

            // Scrollable list of connected clusters only
            ScrollView {
                VStack(spacing: 8) {
                    if !filteredActiveContexts.isEmpty {
                        ForEach(filteredActiveContexts) { ctx in
                            connectedClusterCard(ctx)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                            Text("No matching connected clusters")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 90)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: CGFloat(min(activeContexts.count * 68 + 24, 340)))

            Divider().opacity(0.6)

            // Footer
            HStack {
                Button {
                    isPresented = false
                    backToCTX()
                } label: {
                    Label("Manage Profiles & Connect More", systemImage: "plus.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private func connectedClusterCard(_ ctx: KubernetesContextProfile) -> some View {
        let isCurrent = ctx.id == currentContext.id || ctx.contextName == currentContext.contextName
        let isCLIDefault = store.activeKubeContext == ctx.contextName

        return HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)

            // Cluster Profile Icon (Kubernetes SVG)
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 26, height: 26)
                ProviderIcon(
                    provider: KubernetesProfileAdapter.cloudProfile(from: ctx).provider,
                    size: 15,
                    fallbackTint: .indigo
                )
            }

            // Cluster & Context info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(ctx.cleanClusterName)
                        .font(.system(size: 13, weight: isCurrent ? .bold : .semibold))
                        .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    CTXEnvironmentBadge(environment: ctx.environmentType)
                        .scaleEffect(0.85)

                    if isCLIDefault {
                        Text("CLI")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .help("Active CLI context in ~/.kube/config")
                    }
                }

                Text(ctx.shortSubtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            // Actions: explicitly clear and understandable
            if isCurrent {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Current")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.12), in: Capsule())
            } else {
                HStack(spacing: 6) {
                    // Switch current window to this cluster
                    Button {
                        isPresented = false
                        onSelectCluster(ctx)
                    } label: {
                        Text("Switch")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Switch this window to \(ctx.cleanClusterName)")

                    // Open cluster in a new window beside this one
                    Button {
                        isPresented = false
                        openInNewWindowAction(ctx)
                    } label: {
                        Label("New Window", systemImage: "macwindow.badge.plus")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Open \(ctx.cleanClusterName) in a new window beside this one")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCurrent ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isCurrent ? Color.blue.opacity(0.2) : Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func openInNewWindowAction(_ ctx: KubernetesContextProfile) {
        if let onOpenInNewWindow {
            onOpenInNewWindow(ctx)
        } else {
            openWindow(id: "cluster-workspace", value: ctx.id)
            NSApp.activate(ignoringOtherApps: true)
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
}
