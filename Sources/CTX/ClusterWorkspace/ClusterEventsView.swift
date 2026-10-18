import AppKit
import CTXCore
import SwiftUI

/// Authentic Apple-grade Live Cluster Events Stream (`ClusterEventsView`).
///
/// Replaces the generic table for `.events` with a dedicated, zero-clutter event stream:
/// - Single-row unified header (`CTXUnifiedHeaderBar`) with `All / Warning / Normal` filter,
///   Reason filter menu, search field, and reload button.
/// - Interactive 4-card KPI strip (`CTXInteractiveKpiCard`) for instant filtering.
/// - Clean scannable event rows with `×count` occurrence badges, semantic reason pills,
///   clickable `Kind/name` object badges that jump directly to the inspector, and copy actions.
struct ClusterEventsView: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel

    enum EventTypeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case warning = "Warning"
        case normal = "Normal"
        var id: String { rawValue }
    }

    @State private var typeFilter: EventTypeFilter = .all
    @State private var selectedReason: String = "All Reasons"
    @State private var searchText: String = ""

    private var list: KubernetesResourceList? {
        viewModel.resourceList(for: .events)
    }

    private var allRows: [KubernetesResourceRow] {
        list?.rows ?? []
    }

    private var availableReasons: [String] {
        let reasons = Set(allRows.compactMap { $0.cells["Reason"] }.filter { !$0.isEmpty })
        return ["All Reasons"] + reasons.sorted()
    }

    private var filteredRows: [KubernetesResourceRow] {
        allRows.filter { row in
            let rowType = (row.cells["Type"] ?? "").lowercased()
            switch typeFilter {
            case .all:
                break
            case .warning:
                guard rowType == "warning" else { return false }
            case .normal:
                guard rowType == "normal" else { return false }
            }

            if selectedReason != "All Reasons" {
                guard row.cells["Reason"] == selectedReason else { return false }
            }

            guard !searchText.isEmpty else { return true }
            let q = searchText.lowercased()
            return (row.cells["Object"] ?? "").lowercased().contains(q)
                || (row.cells["Reason"] ?? "").lowercased().contains(q)
                || (row.cells["Message"] ?? "").lowercased().contains(q)
                || (row.cells["Namespace"] ?? "").lowercased().contains(q)
        }
    }

    private var warningCount: Int {
        allRows.filter { ($0.cells["Type"] ?? "").lowercased() == "warning" }.count
    }

    private var normalCount: Int {
        allRows.filter { ($0.cells["Type"] ?? "").lowercased() == "normal" }.count
    }

    private var repeatedEventsCount: Int {
        allRows.filter { (Int($0.cells["Count"] ?? "") ?? 0) > 1 }.count
    }

    private var isLoading: Bool {
        viewModel.isLoading(section: .events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar

            if isLoading && list == nil {
                CTXGlassPanel {
                    CTXLoadingStateView(
                        title: "Loading Cluster Events",
                        message: "Fetching recent Kubernetes events in '\(viewModel.namespace)'...",
                        centered: true
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let list, list.status != .reachable {
                ResourceIssuePanel(
                    section: .events,
                    list: list,
                    retry: { viewModel.loadResource(kind: .events, bypassCache: true) }
                )
            } else if allRows.isEmpty {
                CTXGlassPanel {
                    CTXEmptyStateView(
                        title: "No Cluster Events",
                        message: "Kubernetes has not recorded any recent events in '\(viewModel.namespace)'.",
                        systemImage: "bell.slash"
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                kpiStrip

                if filteredRows.isEmpty {
                    CTXGlassPanel {
                        VStack(spacing: 10) {
                            CTXEmptyStateView(
                                title: "No Matching Events",
                                message: "No events match the active filter criteria.",
                                systemImage: "line.3.horizontal.decrease.circle"
                            )
                            Button("Reset Filters") {
                                typeFilter = .all
                                selectedReason = "All Reasons"
                                searchText = ""
                            }
                            .buttonStyle(CTXSecondaryButton())
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 7) {
                            ForEach(filteredRows.prefix(500)) { row in
                                eventStreamRow(row)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.loadResource(kind: .events, bypassCache: false)
        }
    }

    // MARK: - Unified Single-Row Header

    private var headerBar: some View {
        CTXUnifiedHeaderBar(
            title: "Cluster Events",
            systemImage: "bell.badge.fill",
            iconTint: warningCount > 0 ? .orange : .blue,
            countBadge: filteredRows.count,
            countTint: warningCount > 0 ? .orange : .blue
        ) {
            if warningCount > 0 {
                CTXSemanticPill(
                    text: "\(warningCount) Warnings",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
        } trailingControls: {
            Picker("Type", selection: $typeFilter) {
                ForEach(EventTypeFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 195)

            if availableReasons.count > 2 {
                Menu {
                    ForEach(availableReasons, id: \.self) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack {
                                Text(reason)
                                if selectedReason == reason {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tag")
                            .font(.system(size: 10, weight: .semibold))
                        Text(selectedReason)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.secondary.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.secondary.opacity(0.22), lineWidth: 0.75)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            CTXSearchField(placeholder: "Filter object, reason, message...", text: $searchText)
                .frame(minWidth: 160, idealWidth: 220, maxWidth: 260)
        }
    }

    // MARK: - Interactive 4-Card KPI Strip

    private var kpiStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                kpiCards
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                kpiCards
            }
        }
    }

    @ViewBuilder
    private var kpiCards: some View {
        CTXInteractiveKpiCard(
            title: "Total Events",
            value: "\(allRows.count)",
            subtitle: typeFilter == .all ? "Showing all events" : "Click to show all",
            systemImage: "list.bullet.rectangle.portrait.fill",
            tint: .blue,
            isSelected: typeFilter == .all && selectedReason == "All Reasons"
        ) {
            withAnimation(.easeInOut(duration: 0.15)) {
                typeFilter = .all
                selectedReason = "All Reasons"
            }
        }

        CTXInteractiveKpiCard(
            title: "Warnings",
            value: "\(warningCount)",
            subtitle: "Failed or backoff states",
            systemImage: "exclamationmark.triangle.fill",
            tint: warningCount > 0 ? .orange : .secondary,
            isSelected: typeFilter == .warning
        ) {
            withAnimation(.easeInOut(duration: 0.15)) {
                typeFilter = typeFilter == .warning ? .all : .warning
            }
        }

        CTXInteractiveKpiCard(
            title: "Normal",
            value: "\(normalCount)",
            subtitle: "Scheduled, pulled, started",
            systemImage: "checkmark.circle.fill",
            tint: .green,
            isSelected: typeFilter == .normal
        ) {
            withAnimation(.easeInOut(duration: 0.15)) {
                typeFilter = typeFilter == .normal ? .all : .normal
            }
        }

        CTXInteractiveKpiCard(
            title: "Repeated (×N)",
            value: "\(repeatedEventsCount)",
            subtitle: "Recurring cluster signals",
            systemImage: "repeat.circle.fill",
            tint: .purple,
            isSelected: false
        ) {
            withAnimation(.easeInOut(duration: 0.15)) {
                typeFilter = .warning
            }
        }
    }

    // MARK: - Event Stream Row

    private func eventStreamRow(_ row: KubernetesResourceRow) -> some View {
        let eventType = (row.cells["Type"] ?? "").lowercased()
        let isWarning = eventType == "warning"
        let isNormal = eventType == "normal"
        let tint: Color = isWarning ? .orange : (isNormal ? .green : .secondary)
        let reason = row.cells["Reason"] ?? "—"
        let objectRef = row.cells["Object"] ?? "-"
        let message = row.cells["Message"] ?? ""
        let ns = row.cells["Namespace"] ?? "—"
        let lastSeen = row.cells["Last"] ?? "-"
        let countVal = Int(row.cells["Count"] ?? "")
        let isSelected = viewModel.selectedResource(for: .events)?.id == row.id

        return Button {
            viewModel.selectResource(row, in: .events)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isWarning ? "exclamationmark.triangle.fill" : (isNormal ? "checkmark.circle.fill" : "questionmark.circle.fill"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        CTXSemanticPill(
                            text: reason,
                            tint: isWarning ? .orange : .blue,
                            monospaced: true
                        )

                        objectBadgeButton(objectRef: objectRef, namespace: ns)

                        if viewModel.selectedNamespace == .allNamespaces {
                            Text(ns)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.primary.opacity(0.04), in: Capsule())
                        }

                        Spacer(minLength: 6)

                        if let countVal, countVal > 1 {
                            Text("×\(countVal)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(isWarning ? .orange : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((isWarning ? Color.orange : Color.secondary).opacity(0.14), in: Capsule())
                        }

                        Text(lastSeen)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        CTXCopyIconButton(value: "[\(reason)] \(objectRef) (\(ns)): \(message)")
                    }

                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary.opacity(0.9))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.025))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.55) : (isWarning ? Color.orange.opacity(0.22) : Color.primary.opacity(0.07)),
                        lineWidth: isSelected ? 1.2 : 0.75
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func objectBadgeButton(objectRef: String, namespace: String) -> some View {
        let parts = objectRef.split(separator: "/", maxSplits: 1).map(String.init)
        let rawKind = parts.first ?? ""
        let objName = parts.count > 1 ? parts[1] : objectRef
        let mappedKind = mapKind(rawKind)

        return Group {
            if let kind = mappedKind, !objName.isEmpty {
                Button {
                    Task {
                        await viewModel.navigateToResource(
                            kind: kind,
                            name: objName,
                            namespace: namespace,
                            tab: .overview
                        )
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(rawKind.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                        Text(objName)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Inspect \(objectRef)")
            } else {
                Text(objectRef)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }

    private func mapKind(_ rawKind: String) -> KubernetesResourceKind? {
        switch rawKind.lowercased() {
        case "pod": return .pods
        case "deployment", "statefulset", "daemonset", "replicaset": return .workloads
        case "node": return .nodes
        case "service": return .services
        case "ingress": return .ingress
        case "configmap": return .configMaps
        case "secret": return .secretMetadata
        case "persistentvolumeclaim": return .pvc
        case "horizontalpodautoscaler": return .hpa
        case "cronjob", "job": return .cronJobs
        default: return nil
        }
    }
}
