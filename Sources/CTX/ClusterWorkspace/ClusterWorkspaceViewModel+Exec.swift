import CTXCore
import Foundation
import SwiftUI

extension ClusterWorkspaceViewModel {
    func loadExecContainers(for row: KubernetesResourceRow) {
        guard execContainersPodID != row.id else { return }
        let reference = row.reference(kind: .pods, context: context)
        guard let namespace = reference.namespace else { return }
        execContainersPodID = row.id
        execContainers = []
        selectedExecContainer = nil

        Task { [weak self] in
            guard let self else { return }
            let containers = await logsReader.containers(
                namespace: namespace,
                pod: reference.name,
                context: context
            )
            guard !Task.isCancelled, execContainersPodID == row.id else { return }
            execContainers = containers
            selectedExecContainer = containers.count == 1 ? containers.first : nil
        }
    }

    func selectExecContainer(_ container: String) {
        selectedExecContainer = container
    }

    func openShell(for row: KubernetesResourceRow, container: String?) {
        let reference = row.reference(kind: .pods, context: context)
        guard let namespace = reference.namespace else { return }
        let effectiveContainer = container ?? selectedExecContainer ?? (execContainers.count == 1 ? execContainers.first : nil)
        let request = KubernetesPodExecLauncher.Request(
            namespace: namespace,
            podName: reference.name,
            container: effectiveContainer
        )
        let terminal = UserDefaults.standard.string(forKey: CTXDefaultsKey.terminalApplication) ?? ""
        let subject = "pod/\(reference.name)\(effectiveContainer.map { " --container \($0)" } ?? "") --namespace \(namespace)"
        let contextProfile = context
        let auditLog = auditLog

        podExecDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            podExecResult = nil
        }

        Task.detached(priority: .userInitiated) {
            do {
                try KubernetesPodExecLauncher.open(
                    context: contextProfile,
                    request: request,
                    preferredTerminalBundlePath: terminal
                )
                try? auditLog.record(AuditEvent(
                    type: .podExecOpened,
                    contextName: contextProfile.contextName,
                    message: subject
                ))
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        self.podExecResult = KubernetesLifecycleActionResult(
                            success: true,
                            message: "Opened shell for \(reference.name)\(effectiveContainer.map { " (\($0))" } ?? "")"
                        )
                    }
                    self.schedulePodExecResultDismiss(after: 3.5)
                }
            } catch {
                try? auditLog.record(AuditEvent(
                    type: .podExecFailed,
                    contextName: contextProfile.contextName,
                    message: "\(subject): \(error.localizedDescription)"
                ))
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        self.podExecResult = KubernetesLifecycleActionResult(
                            success: false,
                            message: "Could not open shell: \(error.localizedDescription)",
                            errorDetails: error.localizedDescription
                        )
                    }
                    self.schedulePodExecResultDismiss(after: 6.0)
                }
            }
        }
    }

    private func schedulePodExecResultDismiss(after seconds: TimeInterval) {
        podExecDismissTask?.cancel()
        podExecDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.podExecResult = nil
                }
            }
        }
    }
}
