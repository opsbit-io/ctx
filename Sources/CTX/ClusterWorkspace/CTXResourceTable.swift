import AppKit
import CTXCore
import SwiftUI

/// One column with its resolved on-screen width.
struct ResolvedColumn: Identifiable, Equatable {
    var id: String { column.id }
    let column: CTXTableColumn
    let width: CGFloat
}

/// Shared, kind-agnostic resource table with Apple-grade interactive column sorting,
/// real-time drag resizing, and fluid responsiveness.
///
/// Complies with Apple HIG:
/// - Click column header to sort (with native macOS sort indicator chevrons).
/// - Clean, decluttered headers (no superfluous in-column dropdown menus).
/// - Proportional auto-resolution that avoids artificial giant gaps and prevents text clipping.
/// - Drag handles between columns for seamless manual width adjustments.
struct CTXResourceTable: View {
    let targetKind: KubernetesResourceKind?
    let targetSection: ClusterWorkspaceSection?
    let rows: [KubernetesResourceRow]
    let selectedRowID: String?
    let showsNamespaceColumn: Bool
    let onSelect: (KubernetesResourceRow) -> Void

    init(
        kind: KubernetesResourceKind? = nil,
        section: ClusterWorkspaceSection? = nil,
        rows: [KubernetesResourceRow],
        selectedRowID: String?,
        showsNamespaceColumn: Bool,
        onSelect: @escaping (KubernetesResourceRow) -> Void
    ) {
        self.targetKind = kind
        self.targetSection = section
        self.rows = rows
        self.selectedRowID = selectedRowID
        self.showsNamespaceColumn = showsNamespaceColumn
        self.onSelect = onSelect
    }

    @Environment(\.workspaceContentWidth) private var paneWidth
    @State private var measuredWidth: CGFloat = 0

    // Interactive Column Sorting & Resizing State
    @State private var sortColumnKey: String? = nil
    @State private var sortAscending: Bool = true
    @State private var customWidths: [String: CGFloat] = [:]
    @State private var hoveredHeaderKey: String? = nil

    private var availableWidth: CGFloat {
        let fromPane = paneWidth - ClusterWorkspaceLayout.pagePadding * 2
        if fromPane > 200 { return fromPane }
        return measuredWidth > 200 ? measuredWidth : 900
    }

    @State private var hoveredRowID: String?
    @State private var displayLimit = Self.initialWindow

    static let initialWindow = 100
    private static let windowGrowth = 150
    private static let growthLeadRows = 40

    // Sorted rows
    private var processedRows: [KubernetesResourceRow] {
        var result = rows
        if let sortKey = sortColumnKey {
            result.sort { r1, r2 in
                let v1 = r1.cells[sortKey] ?? ""
                let v2 = r2.cells[sortKey] ?? ""
                let comp = CTXTableValueParser.compare(key: sortKey, a: v1, b: v2)
                let asc = comp == .orderedAscending
                return sortAscending ? asc : !asc
            }
        }
        return result
    }

    private var visibleRows: [KubernetesResourceRow] {
        processedRows.count <= displayLimit ? processedRows : Array(processedRows.prefix(displayLimit))
    }

    private var growthTriggerRowID: String? {
        guard displayLimit < processedRows.count else { return nil }
        let index = max(0, visibleRows.count - Self.growthLeadRows)
        return visibleRows.indices.contains(index) ? visibleRows[index].id : visibleRows.last?.id
    }

    @State private var resolvedColumns: [ResolvedColumn] = []

    private var isCompact: Bool {
        ClusterWorkspaceLayoutMode(width: availableWidth) == .compact
    }

    private var allColumns: [CTXTableColumn] {
        let columns: [CTXTableColumn]
        if let targetSection {
            columns = CTXResourceColumns.columns(for: targetSection)
        } else if let targetKind {
            columns = CTXResourceColumns.columns(for: targetKind)
        } else {
            columns = CTXResourceColumns.columns(for: KubernetesResourceKind.pods)
        }
        return showsNamespaceColumn ? columns : columns.filter { $0.key != "Namespace" }
    }

    private let rowHorizontalPadding: CGFloat = 14
    private let columnSpacing: CGFloat = 12

    var body: some View {
        let resolved = resolvedColumns.isEmpty ? Self.resolve(allColumns, availableWidth: availableWidth, isCompact: isCompact, customWidths: customWidths) : resolvedColumns
        let calculatedWidth = resolved.reduce(rowHorizontalPadding * 2) { $0 + $1.width } + CGFloat(max(0, resolved.count - 1)) * columnSpacing
        let contentWidth = max(availableWidth, calculatedWidth)

        return VStack(alignment: .leading, spacing: 0) {
            CTXGlassPanel(padding: 0) {
                ScrollView(.horizontal) {
                    LazyVStack(spacing: 0) {
                        headerRow(resolved)
                        Divider()
                        ForEach(visibleRows) { row in
                            ResourceRowView(
                                row: row,
                                resolved: resolved,
                                isSelected: row.id == selectedRowID,
                                isHovered: row.id == hoveredRowID,
                                rowHorizontalPadding: rowHorizontalPadding,
                                columnSpacing: columnSpacing,
                                onSelect: onSelect,
                                onHoverChange: { hovering in
                                    if hovering {
                                        hoveredRowID = row.id
                                    } else if hoveredRowID == row.id {
                                        hoveredRowID = nil
                                    }
                                }
                            )
                            .equatable()
                            .onAppear {
                                guard row.id == growthTriggerRowID else { return }
                                displayLimit = min(displayLimit + Self.windowGrowth, processedRows.count)
                            }
                            Divider().opacity(0.45)
                        }

                        if processedRows.count > visibleRows.count {
                            HStack {
                                Spacer()
                                Button {
                                    displayLimit = processedRows.count
                                } label: {
                                    Text("Show all \(processedRows.count) items")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 8)
                                Spacer()
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(width: contentWidth, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TableWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(TableWidthPreferenceKey.self) { newWidth in
            guard abs(newWidth - measuredWidth) > 1 else { return }
            measuredWidth = newWidth
            resolvedColumns = Self.resolve(allColumns, availableWidth: availableWidth, isCompact: isCompact, customWidths: customWidths)
        }
        .onChange(of: paneWidth) { _, _ in
            resolvedColumns = Self.resolve(allColumns, availableWidth: availableWidth, isCompact: isCompact, customWidths: customWidths)
        }
        .onChange(of: targetSection) { _, _ in
            displayLimit = Self.initialWindow
            resolvedColumns = Self.resolve(allColumns, availableWidth: availableWidth, isCompact: isCompact, customWidths: customWidths)
        }
        .onChange(of: targetKind) { _, _ in
            displayLimit = Self.initialWindow
            resolvedColumns = Self.resolve(allColumns, availableWidth: availableWidth, isCompact: isCompact, customWidths: customWidths)
        }
        .onChange(of: rows) { _, newRows in
            displayLimit = min(max(displayLimit, Self.initialWindow), max(newRows.count, Self.initialWindow))
        }
        .onChange(of: showsNamespaceColumn) { _, _ in
            resolvedColumns = Self.resolve(allColumns, availableWidth: availableWidth, isCompact: isCompact, customWidths: customWidths)
        }
    }

    // MARK: - Native Header Row with Click-to-Sort & Drag Resize

    private func headerRow(_ resolved: [ResolvedColumn]) -> some View {
        HStack(spacing: columnSpacing) {
            ForEach(resolved) { resolvedColumn in
                HStack(spacing: 0) {
                    columnHeaderCell(resolvedColumn)

                    // Drag-to-resize divider on the right of each column
                    CTXColumnResizeDivider(
                        onDelta: { delta in
                            let current = customWidths[resolvedColumn.column.key] ?? resolvedColumn.width
                            let newW = max(resolvedColumn.column.minWidth, min(resolvedColumn.column.maxWidth, current + delta))
                            customWidths[resolvedColumn.column.key] = newW
                            resolvedColumns = Self.resolve(allColumns, availableWidth: availableWidth, isCompact: isCompact, customWidths: customWidths)
                        },
                        onReset: {
                            customWidths.removeValue(forKey: resolvedColumn.column.key)
                            resolvedColumns = Self.resolve(allColumns, availableWidth: availableWidth, isCompact: isCompact, customWidths: customWidths)
                        }
                    )
                    .frame(width: 8)
                }
            }
        }
        .padding(.horizontal, rowHorizontalPadding)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
    }

    private func columnHeaderCell(_ resolvedColumn: ResolvedColumn) -> some View {
        let col = resolvedColumn.column
        let isSorted = sortColumnKey == col.key
        let isHovered = hoveredHeaderKey == col.key
        let cellWidth = max(col.minWidth - 8, resolvedColumn.width - 8)

        return Button {
            toggleSort(for: col.key)
        } label: {
            HStack(spacing: 4) {
                if col.alignment == .trailing { Spacer(minLength: 0) }

                Text(col.title)
                    .font(.system(size: 11.5, weight: isSorted ? .bold : .semibold))
                    .foregroundStyle(isSorted ? Color.accentColor : (isHovered ? .primary : .secondary))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if isSorted {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(Color.accentColor)
                }

                if col.alignment == .leading { Spacer(minLength: 0) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredHeaderKey = hovering ? col.key : nil
        }
        .help("Click to sort by \(col.title)")
        .frame(width: cellWidth, alignment: col.alignment == .trailing ? .trailing : .leading)
    }

    private func toggleSort(for key: String) {
        if sortColumnKey == key {
            if sortAscending {
                sortAscending = false
            } else {
                sortColumnKey = nil
            }
        } else {
            sortColumnKey = key
            sortAscending = !CTXTableValueParser.prefersDescendingDefault(key: key)
        }
    }

    // MARK: - Proportional Column Resolution Engine

    static func resolve(_ columns: [CTXTableColumn], availableWidth: CGFloat, isCompact: Bool, customWidths: [String: CGFloat] = [:]) -> [ResolvedColumn] {
        var candidates = isCompact ? columns.filter { !$0.hideOnCompact } : columns
        if candidates.isEmpty { candidates = columns }

        let spacingAndPadding: (Int) -> CGFloat = { count in
            CGFloat(max(0, count - 1)) * 12 + 28
        }

        var byPriorityAscending = candidates.enumerated().sorted { lhs, rhs in
            lhs.element.priority == rhs.element.priority ? lhs.offset > rhs.offset : lhs.element.priority < rhs.element.priority
        }.map(\.element)

        while candidates.count > 1 {
            let minSum = candidates.reduce(0) { sum, col in
                let w = customWidths[col.id] ?? col.minWidth
                return sum + max(col.minWidth, w)
            } + spacingAndPadding(candidates.count)
            guard minSum > availableWidth, let dropped = byPriorityAscending.first(where: { candidate in candidates.contains(where: { $0.id == candidate.id }) }) else { break }
            candidates.removeAll { $0.id == dropped.id }
            byPriorityAscending.removeAll { $0.id == dropped.id }
        }

        let kept = Set(candidates.map(\.id))
        let ordered = columns.filter { kept.contains($0.id) }

        var widths: [CGFloat] = ordered.map { col in
            if let custom = customWidths[col.id] {
                return max(col.minWidth, min(col.maxWidth, custom))
            }
            return col.idealWidth
        }

        let idealSum = widths.reduce(0, +) + spacingAndPadding(ordered.count)
        let extra = availableWidth - idealSum

        if extra > 0 {
            var remainingExtra = extra

            // 1. Give non-flexible columns without custom widths modest breathing room up to their maxWidth
            let nonFlexIndices = ordered.enumerated().filter { idx, col in
                customWidths[col.id] == nil && !(col.isFlexible || col.key == "Name" || col.key == "Image" || col.key == "Message") && widths[idx] < col.maxWidth
            }.map(\.offset)

            if !nonFlexIndices.isEmpty {
                let share = min(remainingExtra / CGFloat(nonFlexIndices.count * 2), 25.0)
                for idx in nonFlexIndices {
                    let col = ordered[idx]
                    let allowedGrowth = max(0, col.maxWidth - widths[idx])
                    let growth = min(share, allowedGrowth)
                    widths[idx] += growth
                    remainingExtra -= growth
                }
            }

            // 2. Flexible columns absorb all remaining extra width so the table fills edge-to-edge
            let flexIndices = ordered.enumerated().filter { idx, col in
                customWidths[col.id] == nil && (col.isFlexible || col.key == "Name" || col.key == "Image" || col.key == "Message")
            }.map(\.offset)

            if !flexIndices.isEmpty && remainingExtra > 0 {
                let addPerCol = remainingExtra / CGFloat(flexIndices.count)
                for idx in flexIndices {
                    widths[idx] += addPerCol
                }
                remainingExtra = 0
            } else if remainingExtra > 0 {
                // 3. Fallback: distribute remaining across all columns without custom widths
                let unconstrained = ordered.enumerated().filter { idx, col in
                    customWidths[col.id] == nil
                }.map(\.offset)
                if !unconstrained.isEmpty {
                    let addPerCol = remainingExtra / CGFloat(unconstrained.count)
                    for idx in unconstrained {
                        widths[idx] += addPerCol
                    }
                    remainingExtra = 0
                }
            }
        } else if extra < 0 {
            // Compress flexible/unconstrained columns down towards minWidth when space is tight
            var deficit = -extra
            let shrinkableIndices = ordered.enumerated().filter { idx, col in
                customWidths[col.id] == nil && widths[idx] > col.minWidth
            }.sorted { a, b in
                let aFlex = ordered[a.offset].isFlexible || ordered[a.offset].key == "Name"
                let bFlex = ordered[b.offset].isFlexible || ordered[b.offset].key == "Name"
                if aFlex != bFlex { return aFlex }
                return a.element.minWidth < b.element.minWidth
            }.map(\.offset)

            for idx in shrinkableIndices {
                guard deficit > 0 else { break }
                let col = ordered[idx]
                let canShrink = widths[idx] - col.minWidth
                let shrink = min(deficit, canShrink)
                widths[idx] -= shrink
                deficit -= shrink
            }
        }

        return zip(ordered, widths).map { ResolvedColumn(column: $0, width: $1) }
    }
}

private struct TableWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 900

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Isolated row view — giving each row its own struct lets SwiftUI identity-diff
/// rows independently.
private struct ResourceRowView: View, Equatable {
    let row: KubernetesResourceRow
    let resolved: [ResolvedColumn]
    let isSelected: Bool
    let isHovered: Bool
    let rowHorizontalPadding: CGFloat
    let columnSpacing: CGFloat
    let onSelect: (KubernetesResourceRow) -> Void
    let onHoverChange: (Bool) -> Void

    static func == (lhs: ResourceRowView, rhs: ResourceRowView) -> Bool {
        lhs.row == rhs.row
            && lhs.isSelected == rhs.isSelected
            && lhs.isHovered == rhs.isHovered
            && lhs.resolved == rhs.resolved
            && lhs.rowHorizontalPadding == rhs.rowHorizontalPadding
            && lhs.columnSpacing == rhs.columnSpacing
    }

    var body: some View {
        HStack(spacing: columnSpacing) {
            ForEach(resolved) { resolvedColumn in
                cell(column: resolvedColumn.column, width: resolvedColumn.width)
            }
        }
        .padding(.horizontal, rowHorizontalPadding)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(background, in: Rectangle())
        .onTapGesture { onSelect(row) }
        .onHover { onHoverChange($0) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovered  { return Color.primary.opacity(0.06) }
        if row.warning { return Color.orange.opacity(0.04) }
        return .clear
    }

    @ViewBuilder
    private func cell(column: CTXTableColumn, width: CGFloat) -> some View {
        let value = row.cells[column.key] ?? "-"
        HStack(spacing: 4) {
            if column.alignment == .trailing { Spacer(minLength: 0) }

            if (column.key == "Status" || column.key == "Ready") && value != "-" {
                statusBadge(value, warning: row.warning)
            } else if (column.key == "CPU" || column.key == "Memory" || column.key == "Disk") && value != "-" {
                telemetryCellBadge(key: column.key, value: value)
            } else if column.key == "Name" && !value.isEmpty && value != "-" {
                TechBrandIconView(name: value)
            } else {
                Text(value)
                    .font(.system(size: 12.5, design: column.monospaced ? .monospaced : .default))
                    .foregroundStyle(row.warning && column.key == "Status" ? .orange : .primary)
                    .lineLimit(column.key == "Message" ? 2 : 1)
                    .truncationMode(.middle)
                    .help(column.isFlexible || column.key == "Message" ? value : "")
                    .multilineTextAlignment(column.alignment == .trailing ? .trailing : .leading)
            }

            if (column.key == "Repo URL" || column.key == "Repository") && value != "-" && isHovered {
                if let url = GitRepositoryURLHelper.webURL(from: value, revision: row.cells["Target"]) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Open repository in browser (\(url.absoluteString))")
                }
            }

            if column.copyable && value != "-" && isHovered {
                CTXCopyIconButton(value: value)
            }

            if column.alignment == .leading { Spacer(minLength: 0) }
        }
        .frame(width: width, alignment: column.alignment == .trailing ? .trailing : .leading)
    }

    private func statusBadge(_ text: String, warning: Bool) -> some View {
        let lower = text.lowercased()
        let isSuccess = lower == "running" || lower == "ready" || lower == "succeeded"
            || lower == "1/1" || lower == "2/2" || lower == "3/3"
        let color: Color = isSuccess ? .green : (warning ? .orange : .secondary)
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func telemetryCellBadge(key: String, value: String) -> some View {
        let isCPU = key == "CPU"
        let isMem = key == "Memory"
        let icon = isCPU ? "cpu" : (isMem ? "memorychip" : "internaldrive")
        let color: Color = isCPU ? .cyan : (isMem ? .purple : .indigo)
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 0.75)
        }
    }
}
