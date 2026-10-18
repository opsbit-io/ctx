import Foundation

public enum KubernetesPodExecLauncherError: LocalizedError, Equatable, Sendable {
    case invalidRequest(String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason): reason
        case .launchFailed(let reason): "Could not open a terminal: \(reason)"
        }
    }
}

/// Builds a narrowly-scoped interactive pod shell command and opens it in the
/// user's configured terminal. CTX never captures the interactive session.
public enum KubernetesPodExecLauncher {
    public struct Request: Equatable, Sendable {
        public let namespace: String
        public let podName: String
        public let container: String?

        public init(namespace: String, podName: String, container: String? = nil) {
            self.namespace = namespace
            self.podName = podName
            self.container = container
        }
    }

    private static let namePattern = try! NSRegularExpression(
        pattern: "^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$"
    )

    public static func validate(_ request: Request) -> String? {
        for (label, value) in [("Namespace", request.namespace), ("Pod", request.podName)] {
            guard matches(value) else {
                return "\(label) name '\(value)' is not a valid Kubernetes name."
            }
        }
        if let container = request.container, !container.isEmpty, !matches(container) {
            return "Container name '\(container)' is not a valid Kubernetes name."
        }
        return nil
    }

    private static func matches(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return namePattern.firstMatch(in: value, range: range) != nil
    }

    public static func arguments(context: KubernetesContextProfile, request: Request) -> [String] {
        var arguments = context.kubeconfigArguments + [
            "exec", "-it", "pod/\(request.podName)",
            "--namespace", request.namespace
        ]
        if let container = request.container, !container.isEmpty {
            arguments += ["--container", container]
        }
        // The payload is a fixed constant. No cluster-derived value is evaluated
        // by the container shell.
        arguments += ["--", "sh", "-c", "command -v bash >/dev/null 2>&1 && exec bash || exec sh"]
        return arguments
    }

    static func launchScript(
        kubectlPath: String,
        arguments: [String],
        environment: [String: String],
        title: String
    ) -> String {
        let exports = environment
            .sorted { $0.key < $1.key }
            .map { "export \($0.key)=\(TerminalLauncher.shellQuoted($0.value))" }
            .joined(separator: "\n")
        let command = ([kubectlPath] + arguments)
            .map(TerminalLauncher.shellQuoted)
            .joined(separator: " ")
        return """
        #!/bin/sh
        \(exports)
        printf '\\033]0;%s\\007' \(TerminalLauncher.shellQuoted(title))
        exec \(command)
        """
    }

    public static func open(
        context: KubernetesContextProfile,
        request: Request,
        kubectl: any KubectlCommandBuilding = KubectlRunner(),
        preferredTerminalBundlePath: String = ""
    ) throws {
        if let reason = validate(request) {
            throw KubernetesPodExecLauncherError.invalidRequest(reason)
        }

        let command: KubectlCommand
        do {
            command = try kubectl.inspectionCommand(
                context: context.contextName,
                arguments: arguments(context: context, request: request)
            )
        } catch {
            throw KubernetesPodExecLauncherError.launchFailed(error.localizedDescription)
        }

        var environment = ProviderCommandEnvironment.overrides()
        environment.merge(context.kubeconfigEnvironment) { _, new in new }
        environment["PATH"] = CLIToolPaths.searchDirs.joined(separator: ":")

        do {
            try TerminalLauncher.openScript(
                launchScript(
                    kubectlPath: command.executablePath,
                    arguments: command.arguments,
                    environment: environment,
                    title: "shell · \(request.podName)"
                ),
                named: TerminalLauncher.sanitizedScriptName(request.podName, fallback: "ctx-pod-shell"),
                preferredTerminalBundlePath: preferredTerminalBundlePath
            )
        } catch {
            throw KubernetesPodExecLauncherError.launchFailed(error.localizedDescription)
        }
    }
}
