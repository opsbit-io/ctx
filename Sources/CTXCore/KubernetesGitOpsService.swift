import Foundation

/// How a GitOps application gets its manifests. An ArgoCD `Application` is not
/// necessarily Git-backed: it can point straight at a Helm chart repository, at an
/// OCI registry, or at a Git repo whose manifests are *rendered* by Helm. Collapsing
/// all of those into "a repo URL" is what makes most dashboards misleading, so the
/// distinction is carried through to the table.
public enum GitOpsSourceKind: String, Equatable, Sendable {
    /// Plain manifests or Kustomize overlays in a Git repository.
    case git = "Git"
    /// A chart pulled from a Helm chart repository (`spec.source.chart` is set).
    case helmChart = "Helm chart"
    /// Manifests in Git that ArgoCD renders with Helm (`spec.source.helm` is set).
    case helmFromGit = "Helm (Git)"
    /// A chart or manifest bundle pulled from an OCI registry.
    case oci = "OCI"
    /// Progressive delivery canary managed by Flagger.
    case canary = "Canary"
    case unknown = "—"
}

public struct GitOpsManagedResource: Identifiable, Equatable, Sendable {
    public var id: String { "\(group)/\(kind)/\(namespace)/\(name)" }
    public let group: String
    public let kind: String
    public let namespace: String
    public let name: String
    public let syncStatus: String
    public let healthStatus: String

    public init(group: String = "", kind: String, namespace: String, name: String, syncStatus: String = "—", healthStatus: String = "—") {
        self.group = group
        self.kind = kind
        self.namespace = namespace
        self.name = name
        self.syncStatus = syncStatus
        self.healthStatus = healthStatus
    }
}

public struct GitOpsApplicationItem: Identifiable, Equatable, Sendable {
    public var id: String { "\(provider)/\(namespace)/\(name)" }
    /// The namespace where the controller's custom resource lives (e.g. "argocd" or "flux-system").
    public var namespace: String
    /// The target / destination namespace where the application's workloads are deployed.
    public var destinationNamespace: String
    public var name: String
    /// "ArgoCD" or "Flux CD".
    public var provider: String
    /// The controller's own resource kind — Application, Kustomization, HelmRelease.
    public var kind: String
    public var sourceKind: GitOpsSourceKind
    public var syncStatus: String
    public var healthStatus: String
    /// Git repository, chart repository, or OCI reference — whichever this app uses.
    public var repoURL: String
    /// Chart name when the source is a chart; unknown for plain Git sources.
    public var chart: String
    /// Path inside the repository, for Git-backed sources.
    public var path: String
    /// What the app is *configured* to track — a branch, tag, or chart version.
    public var targetRevision: String
    /// What is *actually* deployed right now, as the controller reports it.
    public var syncedRevision: String
    /// The ApplicationSet or parent that generated this app, when it wasn't
    /// created directly.
    public var managedBy: String
    /// Additional sources on a multi-source ArgoCD application, beyond the first.
    public var additionalSourceCount: Int
    public var age: String
    /// Latest status message or condition message (e.g. reconciliation error or rollout info).
    public var message: String
    /// Managed Kubernetes resources reported by ArgoCD `status.resources` or Flagger targetRef.
    public var managedResources: [GitOpsManagedResource]
    /// Progressive delivery canary weight percentage (0...100) when `provider == "Flagger"`.
    public var canaryWeightPercent: Int?

    public init(
        namespace: String,
        destinationNamespace: String = "",
        name: String,
        provider: String,
        kind: String,
        sourceKind: GitOpsSourceKind = .unknown,
        syncStatus: String = KubernetesGitOpsService.unknownValue,
        healthStatus: String = KubernetesGitOpsService.unknownValue,
        repoURL: String = KubernetesGitOpsService.unknownValue,
        chart: String = KubernetesGitOpsService.unknownValue,
        path: String = KubernetesGitOpsService.unknownValue,
        targetRevision: String = KubernetesGitOpsService.unknownValue,
        syncedRevision: String = KubernetesGitOpsService.unknownValue,
        managedBy: String = KubernetesGitOpsService.unknownValue,
        additionalSourceCount: Int = 0,
        age: String = KubernetesGitOpsService.unknownValue,
        message: String = "",
        managedResources: [GitOpsManagedResource] = [],
        canaryWeightPercent: Int? = nil
    ) {
        self.namespace = namespace
        self.destinationNamespace = destinationNamespace
        self.name = name
        self.provider = provider
        self.kind = kind
        self.sourceKind = sourceKind
        self.syncStatus = syncStatus
        self.healthStatus = healthStatus
        self.repoURL = repoURL
        self.chart = chart
        self.path = path
        self.targetRevision = targetRevision
        self.syncedRevision = syncedRevision
        self.managedBy = managedBy
        self.additionalSourceCount = additionalSourceCount
        self.age = age
        self.message = message
        self.managedResources = managedResources
        self.canaryWeightPercent = canaryWeightPercent
    }
}

/// Parses what the GitOps controllers actually report.
///
/// Every field comes from the live custom resource. Where a controller has not
/// populated a field, these parsers emit `unknownValue` rather than inventing a
/// plausible default — a row that claims "Synced" because nothing was reported is
/// worse than one that admits it does not know.
public enum KubernetesGitOpsService {
    public static let unknownValue = "—"

    // MARK: - ArgoCD

    public static func parseArgoCDApplications(_ items: [[String: Any]]) -> [GitOpsApplicationItem] {
        items.compactMap { item in
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            guard let name = metadata["name"] as? String, !name.isEmpty else { return nil }
            let spec = item["spec"] as? [String: Any] ?? [:]
            let status = item["status"] as? [String: Any] ?? [:]

            // ArgoCD 2.6+ supports `sources` (plural). The first entry is the one
            // shown; the rest are counted so a multi-source app never silently
            // looks like a single-source one.
            let multiSources = spec["sources"] as? [[String: Any]] ?? []
            let source = (spec["source"] as? [String: Any]) ?? multiSources.first ?? [:]
            let additional = max(0, multiSources.count - 1)

            let repoURL = (source["repoURL"] as? String) ?? ""
            let chart = (source["chart"] as? String) ?? ""
            let path = (source["path"] as? String) ?? ""
            let sourceKind = argoSourceKind(repoURL: repoURL, chart: chart, source: source)

            let destination = spec["destination"] as? [String: Any] ?? [:]
            let destinationNamespace = (destination["namespace"] as? String) ?? ""

            let syncDict = status["sync"] as? [String: Any] ?? [:]
            let rawResources = status["resources"] as? [[String: Any]] ?? []
            let managed = rawResources.compactMap { res -> GitOpsManagedResource? in
                guard let rKind = res["kind"] as? String, let rName = res["name"] as? String else { return nil }
                let rGroup = (res["group"] as? String) ?? ""
                let rNs = (res["namespace"] as? String) ?? destinationNamespace
                let rSync = value(res["status"])
                let rHealth = value((res["health"] as? [String: Any])?["status"])
                return GitOpsManagedResource(group: rGroup, kind: rKind, namespace: rNs, name: rName, syncStatus: rSync, healthStatus: rHealth)
            }
            let opState = status["operationState"] as? [String: Any]
            let opMsg = (opState?["message"] as? String)
                ?? ((status["conditions"] as? [[String: Any]])?.first?["message"] as? String)
                ?? ""

            return GitOpsApplicationItem(
                namespace: (metadata["namespace"] as? String) ?? unknownValue,
                destinationNamespace: destinationNamespace,
                name: name,
                provider: "ArgoCD",
                kind: "Application",
                sourceKind: sourceKind,
                syncStatus: value(syncDict["status"]),
                healthStatus: value((status["health"] as? [String: Any])?["status"]),
                repoURL: value(repoURL),
                chart: value(chart),
                path: value(path),
                targetRevision: value(source["targetRevision"]),
                syncedRevision: shortRevision(syncDict["revision"] as? String),
                managedBy: argoOwner(metadata),
                additionalSourceCount: additional,
                age: relativeAge(from: metadata["creationTimestamp"] as? String),
                message: opMsg,
                managedResources: managed
            )
        }
    }

    /// A chart-sourced app sets `chart` and uses `repoURL` as the *chart repository*;
    /// a Git-sourced app that ArgoCD renders through Helm sets `source.helm` instead.
    /// Both are "Helm" to a user, but they are not the same thing, and the target
    /// revision means something different in each (chart version vs branch/tag).
    static func argoSourceKind(repoURL: String, chart: String, source: [String: Any]) -> GitOpsSourceKind {
        if repoURL.lowercased().hasPrefix("oci://") { return .oci }
        if !chart.isEmpty { return .helmChart }
        if source["helm"] is [String: Any] { return .helmFromGit }
        if !repoURL.isEmpty { return .git }
        return .unknown
    }

    /// Apps produced by an ApplicationSet carry it as an owner reference. Surfacing
    /// it explains why editing the app directly would be reverted.
    private static func argoOwner(_ metadata: [String: Any]) -> String {
        let owners = metadata["ownerReferences"] as? [[String: Any]] ?? []
        guard let owner = owners.first(where: { ($0["kind"] as? String) == "ApplicationSet" }) ?? owners.first,
              let kind = owner["kind"] as? String,
              let name = owner["name"] as? String
        else { return unknownValue }
        return "\(kind)/\(name)"
    }

    // MARK: - Flux

    public static func parseFluxKustomizations(_ items: [[String: Any]]) -> [GitOpsApplicationItem] {
        items.compactMap { item in
            fluxItem(item, kind: "Kustomization", sourceKind: .git) { spec, status in
                let sourceRef = spec["sourceRef"] as? [String: Any] ?? [:]
                return FluxSource(
                    repo: value(sourceRef["name"]),
                    chart: unknownValue,
                    path: value(spec["path"]),
                    target: unknownValue,
                    synced: shortRevision(status["lastAppliedRevision"] as? String)
                )
            }
        }
    }

    public static func parseFluxHelmReleases(_ items: [[String: Any]]) -> [GitOpsApplicationItem] {
        items.compactMap { item in
            fluxItem(item, kind: "HelmRelease", sourceKind: .helmChart) { spec, status in
                // Flux nests the chart under `spec.chart.spec`; `chartRef` is the
                // newer OCI-style form.
                let chartSpec = ((spec["chart"] as? [String: Any])?["spec"] as? [String: Any]) ?? [:]
                let sourceRef = (chartSpec["sourceRef"] as? [String: Any])
                    ?? (spec["chartRef"] as? [String: Any])
                    ?? [:]
                let applied = (status["lastAppliedRevision"] as? String)
                    ?? (status["lastAttemptedRevision"] as? String)
                return FluxSource(
                    repo: value(sourceRef["name"]),
                    chart: value(chartSpec["chart"] ?? sourceRef["name"]),
                    path: unknownValue,
                    target: value(chartSpec["version"]),
                    synced: value(applied)
                )
            }
        }
    }

    private struct FluxSource {
        let repo: String
        let chart: String
        let path: String
        let target: String
        let synced: String
    }

    /// Flux reports readiness through the standard `Ready` condition rather than a
    /// dedicated sync/health pair, so both columns derive from it — including the
    /// "not reported yet" case, which stays unknown instead of defaulting to healthy.
    private static func fluxItem(
        _ item: [String: Any],
        kind: String,
        sourceKind: GitOpsSourceKind,
        source: ([String: Any], [String: Any]) -> FluxSource
    ) -> GitOpsApplicationItem? {
        let metadata = item["metadata"] as? [String: Any] ?? [:]
        guard let name = metadata["name"] as? String, !name.isEmpty else { return nil }
        let spec = item["spec"] as? [String: Any] ?? [:]
        let status = item["status"] as? [String: Any] ?? [:]
        let conditions = status["conditions"] as? [[String: Any]] ?? []
        let ready = conditions.first { ($0["type"] as? String) == "Ready" }

        let syncStatus: String
        let healthStatus: String
        if spec["suspend"] as? Bool == true {
            syncStatus = "Suspended"
            healthStatus = unknownValue
        } else {
            switch ready?["status"] as? String {
            case "True":
                syncStatus = "Synced"
                healthStatus = "Healthy"
            case "False":
                syncStatus = "OutOfSync"
                healthStatus = (ready?["reason"] as? String) ?? "Not Ready"
            default:
                syncStatus = unknownValue
                healthStatus = unknownValue
            }
        }

        let destinationNamespace = (spec["targetNamespace"] as? String) ?? (metadata["namespace"] as? String) ?? ""
        let resolved = source(spec, status)
        let readyMsg = (ready?["message"] as? String) ?? ""
        return GitOpsApplicationItem(
            namespace: (metadata["namespace"] as? String) ?? unknownValue,
            destinationNamespace: destinationNamespace,
            name: name,
            provider: "Flux CD",
            kind: kind,
            sourceKind: sourceKind,
            syncStatus: syncStatus,
            healthStatus: healthStatus,
            repoURL: resolved.repo,
            chart: resolved.chart,
            path: resolved.path,
            targetRevision: resolved.target,
            syncedRevision: resolved.synced,
            age: relativeAge(from: metadata["creationTimestamp"] as? String),
            message: readyMsg
        )
    }

    // MARK: - Flagger (Progressive Delivery Canaries)

    public static func parseFlaggerCanaries(_ items: [[String: Any]]) -> [GitOpsApplicationItem] {
        items.compactMap { item in
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            guard let name = metadata["name"] as? String, !name.isEmpty else { return nil }
            let ns = (metadata["namespace"] as? String) ?? unknownValue
            let spec = item["spec"] as? [String: Any] ?? [:]
            let status = item["status"] as? [String: Any] ?? [:]

            let targetRef = spec["targetRef"] as? [String: Any] ?? [:]
            let targetKind = value(targetRef["kind"])
            let targetName = value(targetRef["name"])

            let analysis = spec["analysis"] as? [String: Any] ?? [:]
            let maxWeight = analysis["maxWeight"] as? Int
            let canaryWeight = status["canaryWeight"] as? Int
            let phase = (status["phase"] as? String) ?? unknownValue
            let isSuspended = (spec["suspend"] as? Bool) == true

            let syncStatus: String
            let healthStatus: String
            let weightPct: Int

            if isSuspended {
                syncStatus = "Suspended"
                healthStatus = "Suspended"
                weightPct = canaryWeight ?? 0
            } else {
                switch phase {
                case "Succeeded", "Initialized":
                    syncStatus = "Synced"
                    healthStatus = "Healthy"
                    weightPct = 100
                case "Failed":
                    syncStatus = "OutOfSync"
                    healthStatus = "Degraded"
                    if let maxWeight, maxWeight > 0, let canaryWeight {
                        weightPct = min(100, Int(round(Double(canaryWeight) / Double(maxWeight) * 100)))
                    } else {
                        weightPct = 0
                    }
                case "Progressing", "Promoting", "Finalising", "Waiting", "WaitingPromotion", "Initializing":
                    syncStatus = "Progressing"
                    healthStatus = phase
                    if let maxWeight, maxWeight > 0, let canaryWeight {
                        weightPct = min(100, Int(round(Double(canaryWeight) / Double(maxWeight) * 100)))
                    } else {
                        weightPct = 0
                    }
                default:
                    syncStatus = phase
                    healthStatus = phase
                    weightPct = 0
                }
            }

            let conditions = status["conditions"] as? [[String: Any]] ?? []
            let msg = (conditions.first?["message"] as? String) ?? ""

            return GitOpsApplicationItem(
                namespace: ns,
                destinationNamespace: ns,
                name: name,
                provider: "Flagger",
                kind: "Canary",
                sourceKind: .canary,
                syncStatus: syncStatus,
                healthStatus: healthStatus,
                repoURL: "\(targetKind)/\(targetName)",
                chart: unknownValue,
                path: value(spec["provider"]),
                targetRevision: maxWeight.map { "max \($0)%" } ?? unknownValue,
                syncedRevision: canaryWeight.map { "\($0)% weight" } ?? unknownValue,
                managedBy: "\(targetKind)/\(targetName)",
                additionalSourceCount: 0,
                age: relativeAge(from: metadata["creationTimestamp"] as? String),
                message: msg,
                managedResources: targetKind == unknownValue || targetName == unknownValue
                    ? []
                    : [GitOpsManagedResource(kind: targetKind, namespace: ns, name: targetName, syncStatus: syncStatus, healthStatus: healthStatus)],
                canaryWeightPercent: canaryWeight == nil ? nil : weightPct
            )
        }
    }

    // MARK: - Shared

    private static func value(_ raw: Any?) -> String {
        guard let text = raw as? String, !text.isEmpty else { return unknownValue }
        return text
    }

    /// Shortens a commit SHA for display while keeping everything that carries
    /// meaning. Chart versions and branch names are not SHAs and are returned
    /// untouched; Flux's `main@sha1:abcdef…` form keeps its branch, because
    /// "which branch" is half of what the field is telling you — dropping it left
    /// a bare hash with no indication of what it was tracking.
    public static func shortRevision(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return unknownValue }

        // Flux: "<branch>@<algorithm>:<digest>" (or the older "<branch>/<digest>").
        for separator in ["@", "/"] where raw.contains(separator) {
            let parts = raw.components(separatedBy: separator)
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            let digest = parts[1].components(separatedBy: ":").last ?? parts[1]
            guard let short = abbreviated(digest) else { continue }
            return "\(parts[0])@\(short)"
        }

        // ArgoCD: a bare SHA, or an OCI digest as "sha256:<digest>".
        let bare = raw.components(separatedBy: ":").last ?? raw
        return abbreviated(bare) ?? raw
    }

    /// Only abbreviates something that is unambiguously a hex digest — a chart
    /// version like "56.2.1" or a tag must survive intact.
    private static func abbreviated(_ candidate: String) -> String? {
        guard candidate.count >= 40, candidate.allSatisfy(\.isHexDigit) else { return nil }
        return String(candidate.prefix(7))
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter = ISO8601DateFormatter()

    static func relativeAge(from timestamp: String?) -> String {
        guard let timestamp, !timestamp.isEmpty else { return unknownValue }
        guard let date = fractionalFormatter.date(from: timestamp) ?? plainFormatter.date(from: timestamp) else {
            return unknownValue
        }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

// MARK: - GitOps Management & Operations

public protocol KubernetesGitOpsManaging: Sendable {
    func sync(
        app: GitOpsApplicationItem,
        context: KubernetesContextProfile,
        prune: Bool
    ) async -> KubernetesLifecycleActionResult

    func refresh(
        app: GitOpsApplicationItem,
        context: KubernetesContextProfile,
        hard: Bool
    ) async -> KubernetesLifecycleActionResult

    func suspend(
        app: GitOpsApplicationItem,
        context: KubernetesContextProfile,
        suspended: Bool
    ) async -> KubernetesLifecycleActionResult
}

public final class KubernetesGitOpsManager: KubernetesGitOpsManaging {
    private let kubectl: any KubectlRunning & KubectlCommandBuilding
    private let timeout: TimeInterval

    public init(
        kubectl: any KubectlRunning & KubectlCommandBuilding = KubectlRunner(),
        timeout: TimeInterval = 15
    ) {
        self.kubectl = kubectl
        self.timeout = timeout
    }

    public func sync(
        app: GitOpsApplicationItem,
        context: KubernetesContextProfile,
        prune: Bool = true
    ) async -> KubernetesLifecycleActionResult {
        let namespace = app.namespace.isEmpty || app.namespace == KubernetesGitOpsService.unknownValue ? "argocd" : app.namespace

        switch app.provider {
        case "ArgoCD":
            let pruneFlag = prune ? "true" : "false"
            let patchPayload = "{\"operation\":{\"sync\":{\"prune\":\(pruneFlag),\"syncStrategy\":{\"hook\":{}}}}}"
            let args = [
                "patch", "application", app.name,
                "--namespace", namespace,
                "--type", "merge",
                "-p", patchPayload
            ]
            return await run(
                args,
                context: context,
                successMessage: "Sync initiated for ArgoCD app '\(app.name)'",
                failureMessage: "Failed to trigger sync for '\(app.name)'"
            )

        case "Flux CD":
            let resourceKind = app.kind.lowercased() == "helmrelease" ? "helmrelease" : "kustomization"
            let timestamp = String(Int(Date().timeIntervalSince1970))
            let args = [
                "annotate", resourceKind, app.name,
                "--namespace", namespace,
                "reconcile.fluxcd.io/requestedAt=\(timestamp)",
                "--overwrite"
            ]
            return await run(
                args,
                context: context,
                successMessage: "Reconciliation initiated for Flux \(app.kind) '\(app.name)'",
                failureMessage: "Failed to trigger reconciliation for '\(app.name)'"
            )

        case "Flagger":
            let args = [
                "annotate", "canary", app.name,
                "--namespace", namespace,
                "flagger.app/manual-promote=true",
                "--overwrite"
            ]
            return await run(
                args,
                context: context,
                successMessage: "Manual promotion initiated for Canary '\(app.name)'",
                failureMessage: "Failed to promote Canary '\(app.name)'"
            )

        default:
            return KubernetesLifecycleActionResult(
                success: false,
                message: "Unsupported provider",
                errorDetails: "Sync action is not supported for provider '\(app.provider)'."
            )
        }
    }

    public func refresh(
        app: GitOpsApplicationItem,
        context: KubernetesContextProfile,
        hard: Bool
    ) async -> KubernetesLifecycleActionResult {
        let namespace = app.namespace.isEmpty || app.namespace == KubernetesGitOpsService.unknownValue ? "argocd" : app.namespace

        switch app.provider {
        case "ArgoCD":
            let refreshType = hard ? "hard" : "normal"
            let args = [
                "annotate", "application", app.name,
                "--namespace", namespace,
                "argocd.argoproj.io/refresh=\(refreshType)",
                "--overwrite"
            ]
            return await run(
                args,
                context: context,
                successMessage: "\(hard ? "Hard refresh" : "Refresh") initiated for ArgoCD app '\(app.name)'",
                failureMessage: "Failed to refresh '\(app.name)'"
            )

        case "Flux CD":
            let resourceKind = app.kind.lowercased() == "helmrelease" ? "helmrelease" : "kustomization"
            let timestamp = String(Int(Date().timeIntervalSince1970))
            let args = [
                "annotate", resourceKind, app.name,
                "--namespace", namespace,
                "reconcile.fluxcd.io/requestedAt=\(timestamp)",
                "--overwrite"
            ]
            return await run(
                args,
                context: context,
                successMessage: "Source refresh initiated for Flux \(app.kind) '\(app.name)'",
                failureMessage: "Failed to refresh Flux source for '\(app.name)'"
            )

        default:
            return KubernetesLifecycleActionResult(
                success: false,
                message: "Unsupported provider",
                errorDetails: "Refresh action is not supported for provider '\(app.provider)'."
            )
        }
    }

    public func suspend(
        app: GitOpsApplicationItem,
        context: KubernetesContextProfile,
        suspended: Bool
    ) async -> KubernetesLifecycleActionResult {
        let namespace = app.namespace.isEmpty || app.namespace == KubernetesGitOpsService.unknownValue ? "flux-system" : app.namespace
        let suspendFlag = suspended ? "true" : "false"
        let patchPayload = "{\"spec\":{\"suspend\":\(suspendFlag)}}"

        switch app.provider {
        case "Flux CD":
            let resourceKind = app.kind.lowercased() == "helmrelease" ? "helmrelease" : "kustomization"
            let args = [
                "patch", resourceKind, app.name,
                "--namespace", namespace,
                "--type", "merge",
                "-p", patchPayload
            ]
            return await run(
                args,
                context: context,
                successMessage: "\(suspended ? "Suspended" : "Resumed") Flux \(app.kind) '\(app.name)'",
                failureMessage: "Failed to \(suspended ? "suspend" : "resume") '\(app.name)'"
            )

        case "Flagger":
            let args = [
                "patch", "canary", app.name,
                "--namespace", namespace,
                "--type", "merge",
                "-p", patchPayload
            ]
            return await run(
                args,
                context: context,
                successMessage: "\(suspended ? "Suspended" : "Resumed") Canary '\(app.name)'",
                failureMessage: "Failed to \(suspended ? "suspend" : "resume") '\(app.name)'"
            )

        default:
            return KubernetesLifecycleActionResult(
                success: false,
                message: "Unsupported provider",
                errorDetails: "Suspend/Resume action is not supported for provider '\(app.provider)'."
            )
        }
    }

    private func run(
        _ arguments: [String],
        context: KubernetesContextProfile,
        successMessage: String,
        failureMessage: String
    ) async -> KubernetesLifecycleActionResult {
        do {
            let args = context.kubeconfigArguments + arguments
            var command = try kubectl.inspectionCommand(context: context.contextName, arguments: args)
            command.environmentOverrides = context.kubeconfigEnvironment

            let result = try await kubectl.run(command, timeout: timeout)
            let trimmedOut = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedErr = KubernetesDiagnosticClassifier.sanitize(result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)

            if result.exitCode == 0 {
                return KubernetesLifecycleActionResult(success: true, message: successMessage, errorDetails: nil, stdout: trimmedOut)
            } else {
                return KubernetesLifecycleActionResult(
                    success: false,
                    message: failureMessage,
                    errorDetails: trimmedErr.isEmpty ? "Process exited with code \(result.exitCode)" : trimmedErr,
                    stdout: trimmedOut
                )
            }
        } catch {
            return KubernetesLifecycleActionResult(
                success: false,
                message: failureMessage,
                errorDetails: error.localizedDescription
            )
        }
    }
}
