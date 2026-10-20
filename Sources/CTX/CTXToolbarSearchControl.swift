import CTXCore
import SwiftUI

/// A compact macOS toolbar search control that expands in place without
/// changing the surrounding split-view hierarchy.
struct CTXToolbarSearchControl: View {
    let prompt: String
    @Binding var state: ToolbarSearchState
    var onSubmit: ((String) -> Void)?

    var body: some View {
        Group {
            if state.isExpanded {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    CTXToolbarSearchField(
                        prompt: prompt,
                        text: queryBinding,
                        onFocusChanged: { state.focusChanged($0) },
                        onSubmit: {
                            let submittedQuery = state.submit()
                            onSubmit?(submittedQuery)
                        },
                        onCancel: collapse
                    )

                    if !state.query.isEmpty {
                        Button {
                            state.setQuery("")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 8)
                .frame(minWidth: 112, idealWidth: 156, maxWidth: 176)
                .frame(height: 24)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        state.activate()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help(prompt)
                .accessibilityLabel(prompt)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.isExpanded)
        .task(id: state.idleCollapseDeadline) {
            guard let deadline = state.idleCollapseDeadline else { return }
            let delay = max(0, deadline.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            state.collapseIfIdle()
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { state.query },
            set: { state.setQuery($0) }
        )
    }

    private func collapse() {
        withAnimation(.easeOut(duration: 0.12)) {
            state.escape()
        }
    }
}
