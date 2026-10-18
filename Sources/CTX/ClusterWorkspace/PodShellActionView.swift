import CTXCore
import SwiftUI

struct PodShellActionView: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel
    let selection: ClusterWorkspaceResourceSelection

    private var status: String { selection.row.cells["Status"] ?? "" }
    private var isRunning: Bool { status == "Running" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("POD SHELL")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.tertiary)

                if viewModel.execContainers.count > 1 {
                    Picker("Container", selection: containerBinding) {
                        ForEach(viewModel.execContainers, id: \.self) { container in
                            Text(container).tag(container)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 180)
                }
            }

            Button {
                viewModel.openShell(for: selection.row, container: selectedContainer)
            } label: {
                Label("Open Shell in Terminal", systemImage: "terminal")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(CTXInlineActionButton())
            .controlSize(.small)
            .disabled(!isRunning)
            .help(actionHelp)
        }
        .task(id: selection.row.id) {
            viewModel.loadExecContainers(for: selection.row)
        }
    }

    private var selectedContainer: String? {
        viewModel.selectedExecContainer ?? (viewModel.execContainers.count == 1 ? viewModel.execContainers.first : nil)
    }

    private var containerBinding: Binding<String> {
        Binding(
            get: { selectedContainer ?? viewModel.execContainers.first ?? "" },
            set: { viewModel.selectExecContainer($0) }
        )
    }

    private var actionHelp: String {
        if !isRunning {
            return "Pod must be Running; current status is \(status.isEmpty ? "unknown" : status)."
        }
        return "Open kubectl exec -it in the configured terminal application."
    }
}
