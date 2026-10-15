import CTXCore
import SwiftUI

/// The map's top controls: lineage search, professional category dropdown filter,
/// health/status filter, count badge, legend popover, and grouped zoom controls.
struct TopologyToolbarView: View {
    @Binding var searchText: String
    @Binding var needsAttentionOnly: Bool
    @Binding var showsInactive: Bool
    @Binding var selectedCategory: TopologyNodeCategory?
    let scale: CGFloat
    let counts: TopologyCountSummary
    @Binding var command: TopologyMapCommand?
    var categoryCounts: [TopologyNodeCategory: Int] = [:]

    @State private var showsLegend = false
    @State private var showsCounts = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            labelledToolbar
            compactToolbar
            stackedToolbar
        }
        .popover(isPresented: $showsLegend, arrowEdge: .bottom) {
            TopologyLegendView()
        }
        .popover(isPresented: $showsCounts, arrowEdge: .bottom) {
            Text(counts.full)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: 320, alignment: .leading)
        }
    }

    // MARK: - Toolbar Layouts

    private var labelledToolbar: some View {
        HStack(spacing: 8) {
            searchField("Find object; use +name+ for lineage")
                .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)

            categoryFilterMenu

            statusFilterMenu

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                countBadge
                legendButton
                labelledZoomControls
            }
            .fixedSize()
        }
    }

    private var compactToolbar: some View {
        HStack(spacing: 6) {
            searchField("Find object · +name+")
                .frame(minWidth: 160, maxWidth: 240)
                .layoutPriority(1)

            categoryFilterMenu

            statusFilterMenu

            Spacer(minLength: 6)

            countBadge
            legendButton
            labelledZoomControls
        }
    }

    private var stackedToolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                searchField("Find object · +name+")
                    .frame(maxWidth: .infinity)
                legendButton
                labelledZoomControls
            }
            HStack(spacing: 6) {
                categoryFilterMenu
                statusFilterMenu
                Spacer()
                countBadge
            }
        }
    }

    // MARK: - Search Field

    private func searchField(_ placeholder: String) -> some View {
        CTXSearchField(placeholder: placeholder, text: $searchText)
            .help("""
            Type part of a name to show matching objects.
            name+ includes downstream dependents.
            +name includes upstream dependencies.
            +name+ includes both directed paths.
            """)
    }

    // MARK: - Professional Dropdown Filter Menus

    private var categoryFilterMenu: some View {
        Menu {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedCategory = nil
                }
            } label: {
                HStack {
                    Text(allCategoriesTitle)
                    if selectedCategory == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(TopologyNodeCategory.allCases, id: \.self) { cat in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedCategory = cat
                    }
                } label: {
                    HStack {
                        let count = categoryCounts[cat] ?? 0
                        Text(count > 0 ? "\(cat.title) (\(count))" : cat.title)
                        if selectedCategory == cat {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let selectedCategory {
                    KubernetesIconView(
                        icon: KubernetesVectorIcon(category: selectedCategory),
                        size: 13,
                        tint: Color(hex: selectedCategory.defaultHexColor),
                        filledBackground: false
                    )
                    Text(selectedCategory.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    if let count = categoryCounts[selectedCategory], count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: selectedCategory.defaultHexColor))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(hex: selectedCategory.defaultHexColor).opacity(0.18), in: Capsule())
                    }
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Category: All")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                selectedCategory != nil
                    ? Color(hex: selectedCategory!.defaultHexColor).opacity(0.12)
                    : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        selectedCategory != nil
                            ? Color(hex: selectedCategory!.defaultHexColor).opacity(0.35)
                            : Color.primary.opacity(0.12),
                        lineWidth: 1
                    )
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter topology by category")
    }

    private var allCategoriesTitle: String {
        let total = categoryCounts.values.reduce(0, +)
        return total > 0 ? "All Categories (\(total))" : "All Categories"
    }

    private var statusFilterMenu: some View {
        let hasActiveFilter = needsAttentionOnly || showsInactive
        return Menu {
            Section("Status & Health") {
                Button {
                    needsAttentionOnly.toggle()
                } label: {
                    HStack {
                        Text("Needs Attention Only")
                        if needsAttentionOnly {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Section("Lifecycle") {
                Button {
                    showsInactive.toggle()
                } label: {
                    HStack {
                        Text("Show Inactive / Completed")
                        if showsInactive {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if hasActiveFilter {
                Divider()
                Button {
                    needsAttentionOnly = false
                    showsInactive = false
                } label: {
                    Text("Reset Filters")
                }
            }
        } label: {
            HStack(spacing: 5) {
                if needsAttentionOnly && showsInactive {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("2 Filters Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                } else if needsAttentionOnly {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Needs Attention")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                } else if showsInactive {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.purple)
                    Text("Inactive Included")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.purple)
                } else {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Filter")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                hasActiveFilter
                    ? (needsAttentionOnly ? Color.orange.opacity(0.12) : Color.purple.opacity(0.12))
                    : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        hasActiveFilter
                            ? (needsAttentionOnly ? Color.orange.opacity(0.35) : Color.purple.opacity(0.35))
                            : Color.primary.opacity(0.12),
                        lineWidth: 1
                    )
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter by health and lifecycle state")
    }

    // MARK: - Count Badge & Legend

    private var countBadge: some View {
        Button {
            showsCounts.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                Text(counts.medium)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(Color.primary.opacity(0.05), in: Capsule())
            .overlay {
                Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(counts.full)
        .accessibilityLabel("Map counts")
        .accessibilityValue(counts.full)
    }

    private var legendButton: some View {
        Button {
            showsLegend.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .medium))
                Text("Legend")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(showsLegend ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(showsLegend ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(showsLegend ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map legend")
    }

    // MARK: - Zoom Controls

    private var labelledZoomControls: some View {
        HStack(spacing: 2) {
            Button {
                command = .zoomOut
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Zoom out (⌘-)")

            Text("\(Int(round(scale * 100)))%")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 36)
                .help("Zoom level")

            Button {
                command = .zoomIn
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Zoom in (⌘+)")

            Divider()
                .frame(height: 12)
                .padding(.horizontal, 2)

            Button {
                command = .fit
            } label: {
                Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Fit map to window")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .fixedSize()
    }
}

// MARK: - Topology Legend View

private struct TopologyLegendView: View {
    private let primaryKinds: [TopologyGraphNodeKind] = [
        .deployment, .statefulSet, .daemonSet, .pod, .cronJob, .job,
        .service, .ingress, .networkPolicy,
        .pvc, .pv, .storageClass,
        .configMap, .secret,
        .serviceAccount, .role, .hpa
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    KubernetesIconView(icon: .topology, size: 16, tint: .accentColor, filledBackground: false)
                    Text("Kubernetes Topology Legend")
                        .font(.headline)
                }

                Text("Resources")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(primaryKinds, id: \.self) { kind in
                        HStack(spacing: 8) {
                            KubernetesIconView(nodeKind: kind, size: 16)
                            Text(kind.title)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }

                Divider()

                Text("Relationships & Edges")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 7) {
                    edgeLegendRow(title: "Workload Ownership (owns/manages)", colorHex: "#6e7681", isDashed: false)
                    edgeLegendRow(title: "Service Routing (fronts/selects)", colorHex: "#d29922", isDashed: true)
                    edgeLegendRow(title: "Ingress Rules (routes)", colorHex: "#e3b341", isDashed: true)
                    edgeLegendRow(title: "Storage (mounts)", colorHex: "#db6d28", isDashed: true)
                    edgeLegendRow(title: "Configuration / Secrets (mounts)", colorHex: "#f778ba", isDashed: true)
                    edgeLegendRow(title: "Autoscaling (scales)", colorHex: "#3fb0ac", isDashed: true)
                }

                Divider()

                Text("Select any card on the map to isolate its full upstream dependencies and downstream dependents. Drag canvas to pan and scroll or pinch to zoom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .frame(width: 400, height: 440)
    }

    private func edgeLegendRow(title: String, colorHex: String, isDashed: Bool) -> some View {
        HStack(spacing: 8) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: 24, y: 5))
            }
            .stroke(
                Color(hex: colorHex),
                style: StrokeStyle(lineWidth: 2, dash: isDashed ? [4, 3] : [])
            )
            .frame(width: 24, height: 10)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
