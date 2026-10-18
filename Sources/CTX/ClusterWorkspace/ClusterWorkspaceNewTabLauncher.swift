import CTXCore
import SwiftUI

/// Workspace tab launcher displayed when a user opens a new window/tab
/// without a pre-assigned context (e.g. clicking '+' in the macOS tab bar or pressing ⌘T).
struct ClusterWorkspaceNewTabLauncher: View {
    @ObservedObject var store: ProfileStore
    let onSelectCluster: (KubernetesContextProfile) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

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
            }
        }
        return results
    }

    private var filteredContexts: [KubernetesContextProfile] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.kubernetesContexts }
        return store.kubernetesContexts.filter {
            $0.contextName.lowercased().contains(q)
                || $0.cleanClusterName.lowercased().contains(q)
                || $0.clusterName.lowercased().contains(q)
        }
    }

    var body: some View {
        CTXGlassPanel {
            VStack(spacing: 22) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox.circle.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.indigo.gradient)

                    Text("Open Cluster Workspace")
                        .font(.system(.title2, weight: .bold))

                    Text("Select an active connection or discovered cluster to open in this tab.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                // Search
                CTXSearchField(placeholder: "Search clusters by name or region...", text: $query)
                    .frame(maxWidth: 420)

                // Quick pick: Active Connections
                if !activeContexts.isEmpty && query.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTIVE CONNECTIONS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        HStack(spacing: 12) {
                            ForEach(activeContexts) { ctx in
                                Button {
                                    onSelectCluster(ctx)
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 8, height: 8)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ctx.cleanClusterName)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(Color.primary)
                                                .lineLimit(1)

                                            Text(ctx.shortSubtitle)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 4)

                                        CTXEnvironmentBadge(environment: ctx.environmentType)
                                            .scaleEffect(0.85)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: 580)
                }

                // All Discovered
                VStack(alignment: .leading, spacing: 8) {
                    Text("DISCOVERED CLUSTERS (\(filteredContexts.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filteredContexts) { ctx in
                                Button {
                                    onSelectCluster(ctx)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "cloud.fill")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(ctx.providerType.tint)
                                            .frame(width: 24, height: 24)
                                            .background(ctx.providerType.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ctx.cleanClusterName)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(Color.primary)
                                                .lineLimit(1)

                                            Text(ctx.shortSubtitle)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 8)

                                        CTXEnvironmentBadge(environment: ctx.environmentType)

                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.blue)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.thinMaterial.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 280)
                }
                .frame(maxWidth: 580)
            }
            .padding(28)
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
