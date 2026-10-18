import CTXCore
import Foundation
import SwiftUI

/// GitOps and Helm loading.
///
/// Neither is a plain `kubectl get <kind>`: GitOps state lives in controller-owned
/// custom resources that may not be installed at all, and Helm's authoritative view
/// comes from the `helm` CLI. Both therefore sit outside `ResourceRefreshCoordinator`
/// and own their loading here, but present the same `KubernetesResourceList` the
/// shared table already knows how to render.
extension ClusterWorkspaceViewModel {

    // MARK: - GitOps

    /// GitOps is read cluster-wide (see `KubernetesGitOpsReader.applications`), so
    /// it deliberately does not reload on a namespace switch — the answer is the
    /// same for every namespace.
    func loadGitOps(bypassCache: Bool = false) {
        if !bypassCache, let loadedAt = gitOpsLoadedAt, Date().timeIntervalSince(loadedAt) <= staleThreshold {
            return
        }
        gitOpsTask?.cancel()
        isLoadingGitOps = true
        let started = Date()
        gitOpsTask = Task { [weak self] in
            guard let self else { return }
            // `defer` rather than a trailing assignment: an early `return` on
            // cancellation would otherwise leave the spinner running forever.
            defer { isLoadingGitOps = false }
            let result = await gitOpsReader.applications(context: context, namespace: selectedNamespace)
            guard !Task.isCancelled else { return }
            gitOpsResult = result
            // A failed read must not blank a screen that already showed real apps.
            if result.status == .reachable || gitOpsList == nil {
                gitOpsList = Self.list(from: result, columns: Self.gitOpsColumns)
                gitOpsLoadedAt = Date()
                if let current = self.selectedGitOpsApp,
                   let updated = result.items.first(where: { $0.id == current.id }) {
                    self.selectedGitOpsApp = updated
                } else if self.selectedGitOpsApp == nil {
                    self.selectedGitOpsApp = result.items.first
                }
            }
            gitOpsTask = nil
            CTXPerfLog.log(
                step: "screen_open",
                contextID: context.id,
                namespace: selectedNamespace.storageValue,
                kind: "gitops",
                cache: .miss,
                durationMs: max(0, Int(Date().timeIntervalSince(started) * 1000)),
                outcome: result.status == .reachable ? .success : .error
            )
        }
    }

    static let gitOpsColumns = [
        "Namespace", "Name", "Provider", "Source", "Status", "Health", "Repo URL", "Target", "Synced", "Age"
    ]

    private static func list(from result: GitOpsReadResult, columns: [String]) -> KubernetesResourceList {
        let rows = result.items.map { item -> KubernetesResourceRow in
            // Multi-source detail belongs in Source, not appended to Name — the
            // Name cell has a copy button, and it must yield the real application
            // name that `kubectl` and `argocd` would accept.
            var source = item.sourceKind.rawValue
            if item.additionalSourceCount > 0 {
                source += " +\(item.additionalSourceCount)"
            }
            let displayNamespace = (!item.destinationNamespace.isEmpty && item.destinationNamespace != KubernetesGitOpsService.unknownValue)
                ? item.destinationNamespace
                : item.namespace

            return KubernetesResourceRow(
                id: item.id,
                cells: [
                    "Namespace": displayNamespace,
                    "Destination": item.destinationNamespace,
                    "Controller NS": item.namespace,
                    "Name": item.name,
                    "Provider": item.provider,
                    "Source": source,
                    "Status": item.syncStatus,
                    "Health": item.healthStatus,
                    "Repo URL": item.repoURL,
                    "Target": item.targetRevision,
                    "Synced": item.syncedRevision,
                    "Age": item.age
                ],
                warning: Self.isUnhealthy(item)
            )
        }
        return KubernetesResourceList(
            kind: .workloads,
            columns: columns,
            rows: rows,
            status: result.status,
            diagnostic: result.diagnostic,
            loadedAt: Date()
        )
    }

    private static func isUnhealthy(_ item: GitOpsApplicationItem) -> Bool {
        let healthy = ["healthy", "synced", "suspended", KubernetesGitOpsService.unknownValue]
        return !healthy.contains(item.healthStatus.lowercased())
            || item.syncStatus.lowercased() == "outofsync"
    }

    /// Copy for the empty state, which has to distinguish three genuinely different
    /// situations: no controller installed, a controller installed with nothing to
    /// show, and a scope that filtered everything out.
    /// Surfaces a partially-failed read: some controllers answered and their apps
    /// are on screen, but at least one could not be read, so the list is incomplete.
    var gitOpsSourceNotice: String? {
        guard let result = gitOpsResult,
              result.status == .reachable,
              let diagnostic = result.diagnostic
        else { return nil }
        return "This list may be incomplete — \(diagnostic.commandKind) could not be read: \(diagnostic.stderrSummary)"
    }

    func matchingGitOpsApplication(for appName: String?) -> GitOpsApplicationItem? {
        guard let raw = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard let items = gitOpsResult?.items else { return nil }
        let clean = raw
            .replacingOccurrences(of: "^(argocd|flux)_", with: "", options: .regularExpression)
            .lowercased()

        return items.first { item in
            let itemLower = item.name.lowercased()
            let destLower = item.destinationNamespace.lowercased()
            return itemLower == raw.lowercased()
                || itemLower == clean
                || itemLower.contains(clean)
                || clean.contains(itemLower)
                || (!destLower.isEmpty && (destLower == clean || clean.contains(destLower)))
        }
    }

    var gitOpsEmptyMessage: String {
        guard let result = gitOpsResult else { return "Loading GitOps applications." }
        if result.installedControllers.isEmpty {
            return "No GitOps or Progressive Delivery controllers detected. CTX checks for ArgoCD Applications, Flux Kustomizations/HelmReleases, and Flagger Canaries."
        }
        let controllers = result.installedControllers.joined(separator: ", ")
        if selectedNamespace != .allNamespaces {
            return "\(controllers) installed — no applications targeting '\(selectedNamespace.displayName)'."
        }
        return "\(controllers) installed — no applications reported on this cluster."
    }

    // MARK: - Telemetry

    /// Live utilisation for the Overview panel.
    ///
    /// Metrics move constantly, so this is the one screen where cached data goes
    /// stale in seconds rather than the workspace's usual thirty. It is refreshed on
    /// a short interval while Overview is on screen and stopped as soon as it isn't
    /// — a background poll against a production cluster nobody is looking at is
    /// exactly the kind of thing that shows up in an API-server audit log.
    static let telemetryRefreshInterval: TimeInterval = 15

    func loadTelemetry(force: Bool = false) {
        if !force, let loadedAt = telemetryLoadedAt,
           Date().timeIntervalSince(loadedAt) <= Self.telemetryRefreshInterval {
            return
        }
        guard telemetryTask == nil || force else { return }
        telemetryTask?.cancel()

        // Memory limits come from the pod list already on hand, in the same scope the
        // metrics read uses, so the two always describe the same set of pods.
        let podRows = resourceList(for: .pods)?.rows ?? []
        let limits = Dictionary(
            podRows.compactMap { row -> (String, Double)? in
                guard let raw = row.cells["Memory Limit"], let limit = Double(raw), limit > 0 else { return nil }
                let namespace = row.namespace.map { "\($0)/" } ?? ""
                return ("\(namespace)\(row.name)", limit)
            },
            uniquingKeysWith: { first, _ in first }
        )
        // Requests come from the same pod rows, summed. Committed capacity is what
        // decides whether anything can still be scheduled, and it is routinely far
        // higher than live utilisation.
        let requests = ClusterResourceRequests(
            cpuCores: podRows.compactMap { Double($0.cells["CPU Request Cores"] ?? "") }.reduce(0, +),
            memoryBytes: podRows.compactMap { Double($0.cells["Memory Request Bytes"] ?? "") }.reduce(0, +)
        )
        let podsByNode = Dictionary(grouping: podRows) { $0.cells["Node"] ?? "" }
            .filter { !$0.key.isEmpty }
            .mapValues { $0.count }
        let scope = selectedNamespace
        let podCount = podRows.isEmpty ? nil : podRows.count

        telemetryTask = Task { [weak self] in
            guard let self else { return }
            defer { telemetryTask = nil }
            let result = await metricsReader.telemetry(
                context: context,
                namespace: scope,
                podCount: podCount,
                podsByNode: podsByNode,
                requests: requests,
                memoryLimitsByPodID: limits
            )
            guard !Task.isCancelled else { return }
            telemetry = result
            telemetryLoadedAt = Date()
        }
    }

    /// The scope the pod-based figures were read for, shown next to them so a
    /// namespace-scoped count is never mistaken for a cluster-wide one.
    var telemetryScopeLabel: String {
        selectedNamespace == .allNamespaces ? "cluster-wide" : selectedNamespace.displayName
    }

    /// Starts the poll. Cancelled by `stopTelemetryUpdates()` when Overview goes away.
    func startTelemetryUpdates() {
        loadTelemetry()
        guard telemetryTimerTask == nil else { return }
        telemetryTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.telemetryRefreshInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                loadTelemetry(force: true)
            }
        }
    }

    func stopTelemetryUpdates() {
        telemetryTimerTask?.cancel()
        telemetryTimerTask = nil
        telemetryTask?.cancel()
        telemetryTask = nil
    }

    // MARK: - Helm

    func loadHelm(bypassCache: Bool = false) {
        if !bypassCache, let loadedAt = helmLoadedAt, Date().timeIntervalSince(loadedAt) <= staleThreshold {
            return
        }
        helmTask?.cancel()
        isLoadingHelm = true
        let started = Date()
        helmTask = Task { [weak self] in
            guard let self else { return }
            defer { isLoadingHelm = false }
            let result = await helmReader.releases(context: context, namespace: selectedNamespace)
            guard !Task.isCancelled else { return }
            helmResult = result
            if result.status == .reachable || helmList == nil {
                helmList = Self.list(from: result)
                helmLoadedAt = Date()
                if let first = result.items.first, self.selectedHelmRelease == nil {
                    self.selectHelmRelease(first)
                } else if let current = self.selectedHelmRelease, !result.items.contains(where: { $0.id == current.id }) {
                    self.selectHelmRelease(result.items.first)
                }
            }
            helmTask = nil
            CTXPerfLog.log(
                step: "screen_open",
                contextID: context.id,
                namespace: selectedNamespace.storageValue,
                kind: "helm",
                cache: .miss,
                durationMs: max(0, Int(Date().timeIntervalSince(started) * 1000)),
                outcome: result.status == .reachable ? .success : .error
            )
        }
    }

    private static func list(from result: HelmReadResult) -> KubernetesResourceList {
        let rows = result.items.map { item in
            KubernetesResourceRow(
                id: item.id,
                cells: [
                    "Namespace": item.namespace,
                    "Name": item.name,
                    "Chart": item.chart,
                    "App Version": item.appVersion,
                    "Revision": String(item.revision),
                    "Status": item.status,
                    "Updated": item.updated
                ],
                // Anything not cleanly deployed is worth flagging: failed,
                // uninstalled, and every pending-* state a stuck upgrade leaves behind.
                warning: item.status.lowercased() != "deployed"
            )
        }
        return KubernetesResourceList(
            kind: .workloads,
            columns: ["Namespace", "Name", "Chart", "App Version", "Revision", "Status", "Updated"],
            rows: rows,
            status: result.status,
            diagnostic: result.diagnostic,
            loadedAt: Date()
        )
    }

    /// Shown when releases were found through the Secret-label fallback, so it is
    /// clear why Chart and App Version read as unknown rather than looking broken.
    var helmSourceNotice: String? {
        guard let result = helmResult, result.source == .releaseSecretLabels, !result.items.isEmpty else { return nil }
        return "Showing release metadata from cluster storage Secrets — chart and app version are stored in the Secret payload."
    }

    var helmEmptyMessage: String {
        guard helmResult != nil else { return "Loading Helm releases." }
        return "No Helm releases in this namespace scope."
    }

    func selectHelmRelease(_ release: HelmReleaseItem?) {
        guard selectedHelmRelease != release else { return }
        selectedHelmRelease = release
        helmValuesYAML = nil
        helmManifestYAML = nil
        helmHistory = []
        helmDetailError = nil
        if release != nil {
            isLoadingHelmDetail = true
            loadSelectedHelmDetail()
        } else {
            isLoadingHelmDetail = false
            helmDetailTask?.cancel()
            helmDetailTask = nil
        }
    }

    func setHelmTab(_ tab: HelmDetailTab) {
        guard helmDetailTab != tab else { return }
        helmDetailTab = tab
        loadSelectedHelmDetail()
    }

    func toggleHelmAllValues() {
        helmIncludeAllValues.toggle()
        helmValuesYAML = nil
        loadSelectedHelmDetail(force: true)
    }

    func loadSelectedHelmDetail(force: Bool = false) {
        guard let release = selectedHelmRelease else { return }
        helmDetailTask?.cancel()

        switch helmDetailTab {
        case .values:
            if !force && helmValuesYAML != nil { return }
            isLoadingHelmDetail = true
            helmDetailError = nil
            helmDetailTask = Task { [weak self] in
                guard let self else { return }
                let result = await self.helmReader.releaseValues(
                    context: self.context,
                    namespace: release.namespace,
                    name: release.name,
                    allValues: self.helmIncludeAllValues
                )
                guard !Task.isCancelled else { return }
                self.isLoadingHelmDetail = false
                switch result {
                case .success(let yaml):
                    self.helmValuesYAML = yaml
                case .failure(let error):
                    self.helmDetailError = error.localizedDescription
                }
            }

        case .manifest:
            if !force && helmManifestYAML != nil { return }
            isLoadingHelmDetail = true
            helmDetailError = nil
            helmDetailTask = Task { [weak self] in
                guard let self else { return }
                let result = await self.helmReader.releaseManifest(
                    context: self.context,
                    namespace: release.namespace,
                    name: release.name
                )
                guard !Task.isCancelled else { return }
                self.isLoadingHelmDetail = false
                switch result {
                case .success(let yaml):
                    self.helmManifestYAML = yaml
                case .failure(let error):
                    self.helmDetailError = error.localizedDescription
                }
            }

        case .history:
            if !force && !helmHistory.isEmpty { return }
            isLoadingHelmDetail = true
            helmDetailError = nil
            helmDetailTask = Task { [weak self] in
                guard let self else { return }
                let result = await self.helmReader.releaseHistory(
                    context: self.context,
                    namespace: release.namespace,
                    name: release.name
                )
                guard !Task.isCancelled else { return }
                self.isLoadingHelmDetail = false
                switch result {
                case .success(let history):
                    self.helmHistory = history
                case .failure(let error):
                    self.helmDetailError = error.localizedDescription
                }
            }
        }
    }

}

extension ClusterWorkspaceViewModel {
    /// Opens a section filtered to the rows a summary counted.
    ///
    /// Setting the section before the focus matters: `selectedSection`'s `didSet`
    /// clears any focus belonging to a different section, so assigning them the
    /// other way round would immediately discard the one just set.
    func focus(_ focus: ResourceFocus) {
        selectedSection = focus.section
        resourceFocus = focus
    }

    // MARK: - GitOps Operations (Sync, Refresh, Suspend/Resume)

    func syncGitOpsApp(_ app: GitOpsApplicationItem, prune: Bool = true) {
        performGitOpsAction(actionName: "Sync (\(app.name))") { [weak self] in
            guard let self else { return KubernetesLifecycleActionResult(success: false, message: "Workspace deallocated") }
            return await self.gitOpsManager.sync(app: app, context: self.context, prune: prune)
        }
    }

    func refreshGitOpsApp(_ app: GitOpsApplicationItem, hard: Bool = false) {
        let label = hard ? "Hard Refresh (\(app.name))" : "Refresh (\(app.name))"
        performGitOpsAction(actionName: label) { [weak self] in
            guard let self else { return KubernetesLifecycleActionResult(success: false, message: "Workspace deallocated") }
            return await self.gitOpsManager.refresh(app: app, context: self.context, hard: hard)
        }
    }

    func toggleSuspendGitOpsApp(_ app: GitOpsApplicationItem) {
        let isCurrentlySuspended = app.syncStatus.lowercased() == "suspended"
        let newSuspended = !isCurrentlySuspended
        let label = (newSuspended ? "Suspend" : "Resume") + " (\(app.name))"
        performGitOpsAction(actionName: label) { [weak self] in
            guard let self else { return KubernetesLifecycleActionResult(success: false, message: "Workspace deallocated") }
            return await self.gitOpsManager.suspend(app: app, context: self.context, suspended: newSuspended)
        }
    }

    private func performGitOpsAction(actionName: String, action: @escaping () async -> KubernetesLifecycleActionResult) {
        gitOpsActionDismissTask?.cancel()
        isPerformingGitOpsAction = true
        withAnimation(.easeOut(duration: 0.15)) {
            gitOpsActionResult = nil
        }

        Task { [weak self] in
            guard let self else { return }
            let result = await action()
            let eventType: AuditEventType = result.success ? .gitOpsActionTriggered : .gitOpsActionFailed
            try? self.auditLog.record(AuditEvent(
                type: eventType,
                contextName: self.context.contextName,
                message: "\(actionName): \(result.message)\(result.errorDetails.map { " - \($0)" } ?? "")"
            ))

            await MainActor.run {
                self.isPerformingGitOpsAction = false
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    self.gitOpsActionResult = result
                }
                if result.success {
                    // Refresh GitOps state after a short delay so controller has time to reflect status change
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        self?.loadGitOps(bypassCache: true)
                    }
                }
                self.scheduleGitOpsResultDismiss(after: result.success ? 3.5 : 6.0)
            }
        }
    }

    private func scheduleGitOpsResultDismiss(after seconds: TimeInterval) {
        gitOpsActionDismissTask?.cancel()
        gitOpsActionDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.gitOpsActionResult = nil
                }
            }
        }
    }
}
