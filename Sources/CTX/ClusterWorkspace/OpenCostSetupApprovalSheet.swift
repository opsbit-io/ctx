import AppKit
import CTXCore
import SwiftUI

struct OpenCostSetupApprovalSheet: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel

    @State private var hasApprovedNonProdMutation: Bool = false
    @State private var productionClusterConfirmation: String = ""
    @State private var showTechnicalInspector: Bool = false
    @State private var inspectorTab: InspectorTab = .command
    @State private var copiedCommand: Bool = false
    @State private var copiedManifest: Bool = false
    @State private var copiedRemediation: Bool = false

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case command = "Helm CLI Command"
        case manifest = "Server-Validated YAML"
        case resources = "Resource Specification"

        var id: String { rawValue }
    }

    private var report: OpenCostSetupPreflightReport? {
        viewModel.openCostPreflightReport
    }

    private var requiredClusterName: String {
        viewModel.title
    }

    private var isApprovalComplete: Bool {
        guard let report, report.canProceedToInstall else { return false }
        if report.isProduction {
            return productionClusterConfirmation.trimmingCharacters(in: .whitespacesAndNewlines) == requiredClusterName
        }
        return hasApprovedNonProdMutation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, 22)
                .padding(.vertical, 15)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.isRunningOpenCostPreflight && report == nil {
                        preflightLoadingCard
                    } else if let report {
                        compactPreflightGrid(report)

                        if !report.canProceedToInstall, let remediation = report.remediationSummary, !remediation.isEmpty {
                            remediationCard(remediation)
                        }

                        if report.canProceedToInstall {
                            deploymentSummaryAndInspectorCard(report)
                        }

                        if viewModel.isInstallingOpenCost || !viewModel.openCostSetupStepLogs.isEmpty || viewModel.openCostSetupResult != nil {
                            executionProgressSection
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }

            Divider()

            footerSection
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
        }
        .frame(
            width: 720,
            height: showTechnicalInspector || !viewModel.openCostSetupStepLogs.isEmpty ? 660 : 515
        )
        .animation(.easeInOut(duration: 0.18), value: showTechnicalInspector)
        .animation(.easeInOut(duration: 0.18), value: viewModel.openCostSetupStepLogs.count)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(report?.existingProviderEndpoint == nil ? "Deploy OpenCost" : "Repair OpenCost")
                        .font(.system(size: 16, weight: .bold))

                    Text(requiredClusterName)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                        .fixedSize(horizontal: true, vertical: false)

                    if viewModel.isProduction {
                        Text("PRODUCTION")
                            .font(.system(size: 9.5, weight: .heavy))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text("Installs the official CNCF OpenCost Helm release in read-only mode, wired to your in-cluster Prometheus.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !viewModel.isInstallingOpenCost {
                Button {
                    hasApprovedNonProdMutation = false
                    productionClusterConfirmation = ""
                    viewModel.runOpenCostPreflight()
                } label: {
                    HStack(spacing: 5) {
                        if viewModel.isRunningOpenCostPreflight {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Re-run Checks")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isRunningOpenCostPreflight)
            }
        }
    }

    // MARK: - Loading State

    private var preflightLoadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 3) {
                Text("Validating cluster readiness & executing server-side admission dry-run…")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Checking Helm CLI, verifying RBAC permissions (`kubectl auth can-i`), discovering Prometheus endpoints, and validating the release manifest against \(requiredClusterName).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 2x2 Compact Verified Cards

    private func compactPreflightGrid(_ report: OpenCostSetupPreflightReport) -> some View {
        let helmCheck = report.checks.first { $0.id == "cli-helm" }
        let rbacCheck = report.checks.first { $0.id == "rbac-permissions" }
        let promCheck = report.checks.first { $0.id == "prometheus-discovery" }
        let dryRunCheck = report.checks.first { $0.id == "server-dry-run" } ?? report.checks.first { $0.id == "storageclass-check" }

        let helmShort = report.helmVersion?.components(separatedBy: "+").first
        let chartSummary = [
            report.chartVersion,
            report.appVersion.map { "App v\($0)" },
            helmShort.map { "Helm \($0)" }
        ].compactMap { $0 }.joined(separator: " · ")

        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            compactStatusCard(
                title: "Chart & Container Image",
                status: helmCheck?.status ?? .failed,
                badge: (helmCheck?.status == .passed) ? "VALIDATED" : "MISSING",
                primaryValue: chartSummary.nonEmpty ?? (helmCheck?.detail ?? "Helm CLI unavailable"),
                secondaryValue: report.containerImage.map { "Image: \($0)" } ?? (report.helmExecutablePath ?? "Install Helm CLI to continue")
            )

            compactStatusCard(
                title: "RBAC Authorization",
                status: rbacCheck?.status ?? .failed,
                badge: (rbacCheck?.status == .passed) ? "AUTHORIZED" : "DENIED",
                primaryValue: (rbacCheck?.status == .passed)
                    ? "6 / 6 cluster & namespace permissions"
                    : (rbacCheck?.detail ?? "Insufficient RBAC permissions"),
                secondaryValue: "Verified via kubectl auth can-i (Namespace, RBAC, Workloads)"
            )

            if let prom = report.discoveredPrometheus {
                compactStatusCard(
                    title: "Prometheus Metrics Source",
                    status: promCheck?.status ?? .passed,
                    badge: prom.hasReadyEndpoints ? "CONNECTED" : "NOT READY",
                    primaryValue: "\(prom.serviceName):\(String(prom.port))",
                    secondaryValue: "Namespace: \(prom.namespace) · Active Prometheus pod verified"
                )
            } else {
                compactStatusCard(
                    title: "Metrics Source",
                    status: report.storageClassInfo.defaultClasses.count == 1 ? .passed : .failed,
                    badge: report.storageClassInfo.defaultClasses.count == 1 ? "COLLECTOR" : "BLOCKED",
                    primaryValue: report.storageClassInfo.defaultClasses.count == 1
                        ? "OpenCost Collector · 1 GiB PVC"
                        : "No safe metrics backend",
                    secondaryValue: report.storageClassInfo.defaultClasses.count == 1
                        ? "StorageClass: \(report.storageClassInfo.defaultClasses[0])"
                        : "Requires one default StorageClass or Ready Prometheus"
                )
            }

            compactStatusCard(
                title: "Admission Dry-Run",
                status: dryRunCheck?.status ?? .passed,
                badge: report.serverDryRunVerified ? "PASSED" : (dryRunCheck?.status == .failed ? "REJECTED" : "READY"),
                primaryValue: report.serverDryRunVerified
                    ? "API server accepted \(report.plannedResources.count) resources (--dry-run=server)"
                    : (dryRunCheck?.detail ?? "Stateless release configuration"),
                secondaryValue: report.discoveredPrometheus?.hasReadyEndpoints == true
                    ? "Uses existing Prometheus · no PVC"
                    : "Collector mode · persistent 1 GiB PVC"
            )
        }
    }

    private func compactStatusCard(
        title: String,
        status: OpenCostCheckStatus,
        badge: String,
        primaryValue: String,
        secondaryValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: iconName(for: status))
                    .foregroundStyle(color(for: status))
                    .font(.system(size: 12, weight: .bold))

                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(badge)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color(for: status).opacity(0.14), in: Capsule())
                    .foregroundStyle(color(for: status))
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(primaryValue)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)

            Text(secondaryValue)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(for: status).opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(color(for: status).opacity(0.22), lineWidth: 0.75)
        }
    }

    // MARK: - Remediation Card (When Blocked)

    private func remediationCard(_ remediation: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Deployment Blocked — Prerequisite Missing", systemImage: "xmark.octagon.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.red)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(remediation, forType: .string)
                    copiedRemediation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedRemediation = false
                    }
                } label: {
                    Label(copiedRemediation ? "Copied" : "Copy Remediation", systemImage: copiedRemediation ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("CTX blocks partial installations when cluster prerequisites are not met. Complete the remediation below and click Re-run Checks:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(remediation)
                .font(.system(size: 11, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.25), lineWidth: 1)
        }
    }

    // MARK: - Release Specification & Collapsible Inspector

    private func deploymentSummaryAndInspectorCard(_ report: OpenCostSetupPreflightReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Release Specification")
                            .font(.system(size: 12, weight: .bold))
                        Text("namespace: \(report.targetNamespace)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    Text("\(report.existingProviderEndpoint == nil ? "Installs" : "Updates") one Helm release; rollback is automatic on failure.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.formattedCommandPreview, forType: .string)
                    copiedCommand = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedCommand = false
                    }
                } label: {
                    Label(copiedCommand ? "Copied" : "Copy Helm Command", systemImage: copiedCommand ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showTechnicalInspector.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(showTechnicalInspector ? "Hide Manifest & CLI" : "View Manifest & CLI")
                        Image(systemName: showTechnicalInspector ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Crisp 3x2 Resource Grid (Zero Truncation)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 6
            ) {
                ForEach(report.plannedResources) { res in
                    HStack(spacing: 6) {
                        Text(res.kind)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(res.kind == "Service" ? "\(res.name):9003" : res.name)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
                }
            }

            if showTechnicalInspector {
                Divider().opacity(0.5)

                HStack {
                    Picker("", selection: $inspectorTab) {
                        ForEach(InspectorTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 440)

                    Spacer()

                    if inspectorTab == .manifest, let yaml = report.renderedManifestYAML {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(yaml, forType: .string)
                            copiedManifest = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedManifest = false
                            }
                        } label: {
                            Label(copiedManifest ? "Copied YAML" : "Copy YAML", systemImage: copiedManifest ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                switch inspectorTab {
                case .command:
                    ScrollView {
                        Text(readableMultilineCommandPreview(report))
                            .font(.system(size: 10.5, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 150)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                case .manifest:
                    ScrollView {
                        Text(report.renderedManifestYAML ?? "# Server dry-run manifest unavailable")
                            .font(.system(size: 10, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 150)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                case .resources:
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(report.plannedResources) { resource in
                            HStack(alignment: .top, spacing: 8) {
                                Text(resource.kind)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .frame(width: 130, alignment: .leading)
                                    .foregroundStyle(Color.accentColor)
                                Text(resource.summary)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        }
    }

    private func readableMultilineCommandPreview(_ report: OpenCostSetupPreflightReport) -> String {
        report.commandArgumentsPreview.map { args in
            guard args.count > 6 else { return args.joined(separator: " ") }
            var lines: [String] = []
            var current = ""
            var i = 0
            while i < args.count {
                let token = args[i]
                if token.hasPrefix("--") && !current.isEmpty {
                    lines.append(current)
                    if i + 1 < args.count && !args[i + 1].hasPrefix("--") {
                        current = "  \(token) \(args[i + 1])"
                        i += 2
                        continue
                    } else {
                        current = "  \(token)"
                        i += 1
                        continue
                    }
                } else {
                    current = current.isEmpty ? token : "\(current) \(token)"
                    i += 1
                }
            }
            if !current.isEmpty {
                lines.append(current)
            }
            return lines.joined(separator: " \\\n")
        }.joined(separator: "\n\n")
    }

    // MARK: - Live Execution Progress

    private var executionProgressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Deployment & Verification Progress")
                    .font(.system(size: 12, weight: .bold))
                if viewModel.isInstallingOpenCost {
                    ProgressView().controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(viewModel.openCostSetupStepLogs) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: iconName(for: step.status))
                            .foregroundStyle(color(for: step.status))
                            .font(.system(size: 11.5, weight: .bold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.step)
                                .font(.system(size: 11, weight: .semibold))
                            Text(step.detail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                    }
                    .padding(7)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            if let result = viewModel.openCostSetupResult {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: result.success ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                        .foregroundStyle(result.success ? .green : .red)
                        .font(.system(size: 15))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.success ? "OpenCost Deployment Verified" : "OpenCost Deployment Failed")
                            .font(.system(size: 12, weight: .bold))
                        Text(result.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(10)
                .background((result.success ? Color.green : Color.red).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Pinned Footer (Always Visible Without Scrolling)

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let report, report.canProceedToInstall, viewModel.openCostSetupResult?.success != true {
                if report.isProduction {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 13.5))

                        Text("Production target — enter")
                            .font(.system(size: 11.5, weight: .medium))
                            .fixedSize(horizontal: true, vertical: false)

                        Text(requiredClusterName)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .fixedSize(horizontal: true, vertical: false)

                        Text("to authorize:")
                            .font(.system(size: 11.5, weight: .medium))
                            .fixedSize(horizontal: true, vertical: false)

                        TextField(requiredClusterName, text: $productionClusterConfirmation)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(width: 200)
                            .disabled(viewModel.isInstallingOpenCost)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 0.75)
                    }
                } else {
                    Toggle(isOn: $hasApprovedNonProdMutation) {
                        Text("I authorize deploying OpenCost (\(report.plannedResources.count) resources) in namespace `\(report.targetNamespace)` on `\(requiredClusterName)`.")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .toggleStyle(.checkbox)
                    .disabled(viewModel.isInstallingOpenCost)
                }
            }

            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text("Audit trail logged to ~/.config/ctx/audit.jsonl")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.openCostSetupResult?.success == true {
                    Button("Done") {
                        viewModel.dismissOpenCostSetupWorkflow()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") {
                        viewModel.dismissOpenCostSetupWorkflow()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(viewModel.isInstallingOpenCost)

                    Button {
                        viewModel.executeApprovedOpenCostInstall()
                    } label: {
                        HStack(spacing: 6) {
                            if viewModel.isInstallingOpenCost {
                                ProgressView().controlSize(.small)
                                Text("Deploying & Verifying…")
                            } else {
                                Image(systemName: "checkmark.shield.fill")
                                Text("Deploy OpenCost")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isProduction ? .orange : .accentColor)
                    .disabled(!isApprovalComplete || viewModel.isInstallingOpenCost || viewModel.isRunningOpenCostPreflight)
                }
            }
        }
    }

    // MARK: - Style Helpers

    private func iconName(for status: OpenCostCheckStatus) -> String {
        switch status {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func color(for status: OpenCostCheckStatus) -> Color {
        switch status {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
