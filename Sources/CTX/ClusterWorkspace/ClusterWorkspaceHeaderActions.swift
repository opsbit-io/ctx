import CTXCore
import SwiftUI

struct ClusterWorkspaceHeaderActions: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel
    let store: ProfileStore

    private var profile: CloudProfile? {
        store.profiles.first {
            $0.provider == .kubernetes && $0.name == viewModel.context.contextName
        }
    }

    private var isCLIDefault: Bool {
        store.activeKubeContext == viewModel.context.contextName
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wideActions
            compactActions
        }
    }

    private var wideActions: some View {
        HStack(spacing: 8) {
            if let profile {
                if isCLIDefault {
                    Label("CLI Default", systemImage: "checkmark.circle.fill")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        .help("This cluster is the current-context for external terminals")
                } else {
                    Button {
                        store.setActive(profile, from: .mainWindow)
                    } label: {
                        Label("Set as CLI Default", systemImage: "terminal")
                            .font(.system(.caption, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Set this cluster as current-context in ~/.kube/config for external terminals")
                }
            }

            ClusterWorkspaceHealthMenu(viewModel: viewModel, store: store)
            refreshButton
        }
    }

    private var compactActions: some View {
        HStack(spacing: 6) {
            ClusterWorkspaceHealthMenu(viewModel: viewModel, store: store)
            refreshButton

            if let profile {
                Menu {
                    if isCLIDefault {
                        Label("CLI Default", systemImage: "checkmark.circle.fill")
                    } else {
                        Button {
                            store.setActive(profile, from: .mainWindow)
                        } label: {
                            Label("Set as CLI Default", systemImage: "terminal")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More cluster actions")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("More cluster actions")
            }
        }
    }

    private var refreshButton: some View {
        CTXReloadIconButton(
            action: { viewModel.refreshCurrentScreen() },
            isLoading: viewModel.isRefreshingCurrentScreen
        )
        .help("Refresh current screen (⌘R)")
    }
}
