import CTXCore
import SwiftUI

struct TopologyCanvasRenderer {
    let graph: ClusterTopologyGraph
    let layout: TopologyGraphLayout.Result
    let labels: [String: String]
    let scale: CGFloat
    let highlighted: Set<String>?
    let selectedNodeID: String?
    let hoveredNodeID: String?

    func draw(in context: GraphicsContext) {
        drawEdges(in: context)
        drawNodes(in: context)
    }

    private func drawEdges(in context: GraphicsContext) {
        for edge in graph.edges {
            guard let (start, end) = layout.anchors(from: edge.source, to: edge.target) else { continue }
            let isLit = highlighted.map { $0.contains(edge.source) && $0.contains(edge.target) } ?? true
            let leadsToFault = graph.node(edge.target)?.health.needsAttention == true

            let baseColor = Color(hex: edge.kind.defaultHexColor)
            let color: Color = !isLit
                ? Color.secondary
                : (leadsToFault ? Color.red : (highlighted == nil ? baseColor : Color.accentColor))

            let opacity: Double = isLit ? (highlighted == nil ? 0.65 : 0.95) : 0.08
            let lineWidth: CGFloat = (isLit && highlighted != nil ? 1.8 : 1.2) / max(scale, 0.4)

            // Draw directional connection curve
            let curvePath = curve(from: start, to: CGPoint(x: end.x - 6, y: end.y))
            let isDashed = edge.kind != .owns

            if isDashed {
                context.stroke(
                    curvePath,
                    with: .color(color.opacity(opacity)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [4, 3])
                )
            } else {
                context.stroke(
                    curvePath,
                    with: .color(color.opacity(opacity)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }

            // Draw directional arrowhead at target node
            var arrow = Path()
            let tip = CGPoint(x: end.x - 1, y: end.y)
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: tip.x - 6, y: tip.y - 3.5))
            arrow.addLine(to: CGPoint(x: tip.x - 6, y: tip.y + 3.5))
            arrow.closeSubpath()

            context.fill(arrow, with: .color(color.opacity(opacity)))
        }
    }

    private func drawNodes(in context: GraphicsContext) {
        for node in graph.nodes {
            guard let frame = layout.frame(node.id) else { continue }
            let isAnchor = node.id == selectedNodeID
            let isHovered = node.id == hoveredNodeID
            let alpha = (highlighted?.contains(node.id) ?? true) ? 1.0 : 0.22
            let effectiveKind = node.effectiveKind
            let tint = Color(hex: effectiveKind.defaultHexColor)

            // 1. Card container shape
            let cardRect = frame
            let card = Path(roundedRect: cardRect, cornerRadius: 10, style: .continuous)

            // Card background: clean macOS translucent surface
            let bgFillColor = isAnchor
                ? Color.accentColor.opacity(0.18 * alpha)
                : (isHovered ? Color.primary.opacity(0.10 * alpha) : Color.primary.opacity(0.05 * alpha))
            context.fill(card, with: .color(bgFillColor))

            // Card border
            let borderColor = border(node, isAnchor: isAnchor, isHovered: isHovered)
            let borderWidth: CGFloat = (isAnchor ? 2.0 : (isHovered ? 1.4 : 1.0)) / max(scale, 0.5)
            context.stroke(card, with: .color(borderColor.opacity(alpha)), lineWidth: borderWidth)

            // 2. Left Icon Badge Tile (34x34)
            let tileRect = CGRect(x: cardRect.minX + 8, y: cardRect.midY - 17, width: 34, height: 34)
            let tile = Path(roundedRect: tileRect, cornerRadius: 8, style: .continuous)
            context.fill(tile, with: .color(tint.opacity(0.15 * alpha)))
            context.stroke(tile, with: .color(tint.opacity(0.32 * alpha)), lineWidth: 1)

            // Draw crisp SVG vector icon inside tile (18x18)
            let iconRect = CGRect(x: tileRect.midX - 9, y: tileRect.midY - 9, width: 18, height: 18)
            let vectorIcon = KubernetesVectorIcon(nodeKind: effectiveKind)
            vectorIcon.draw(in: context, rect: iconRect, color: tint.opacity(alpha), lineWidth: 1.5)

            // 3. Two-Line Typography: Name (bold) + Kind & Subtitle
            let textStartX = tileRect.maxX + 9
            let statusRightSpace: CGFloat = node.issueCount > 0 ? 28 : 20
            let availableTextWidth = max(0, cardRect.maxX - statusRightSpace - textStartX)

            let rawName = labels[node.id] ?? node.name
            let truncatedName = Self.truncatedForCanvas(rawName, maxWidth: availableTextWidth, fontSize: 11)

            // Top line: Name
            context.draw(
                Text(truncatedName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(alpha)),
                at: CGPoint(x: textStartX, y: cardRect.midY - 8),
                anchor: .leading
            )

            // Bottom line: Kind / Subtitle
            let subtitleText = node.subtitle.isEmpty ? effectiveKind.title : node.subtitle
            let truncatedSubtitle = Self.truncatedForCanvas(subtitleText, maxWidth: availableTextWidth, fontSize: 9)
            context.draw(
                Text(truncatedSubtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(tint.opacity(0.85 * alpha)),
                at: CGPoint(x: textStartX, y: cardRect.midY + 8),
                anchor: .leading
            )

            // 4. Status Indicator (Right)
            if node.issueCount > 0 {
                let badge = CGRect(x: cardRect.maxX - 22, y: cardRect.midY - 8, width: 16, height: 16)
                context.fill(Path(ellipseIn: badge), with: .color(Color.orange.opacity(0.95 * alpha)))
                context.draw(
                    Text("\(node.issueCount)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(alpha)),
                    at: CGPoint(x: badge.midX, y: badge.midY)
                )
            } else {
                let dotRect = CGRect(x: cardRect.maxX - 16, y: cardRect.midY - 3.5, width: 7, height: 7)
                let dotColor = node.health.topologyTint
                context.fill(Path(ellipseIn: dotRect), with: .color(dotColor.opacity(alpha)))
            }
        }
    }

    /// A character-count estimate for text truncation inside the canvas.
    private static func truncatedForCanvas(_ text: String, maxWidth: CGFloat, fontSize: CGFloat = 11) -> String {
        guard maxWidth > 0 else { return "" }
        let averageGlyphWidth = fontSize * 0.54
        let budget = max(1, Int(maxWidth / averageGlyphWidth))
        guard text.count > budget else { return text }
        guard budget > 1 else { return "…" }
        return String(text.prefix(budget - 1)) + "…"
    }

    private func curve(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        let reach = max((end.x - start.x) * 0.45, 24)
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + reach, y: start.y),
            control2: CGPoint(x: end.x - reach, y: end.y)
        )
        return path
    }

    private func border(_ node: TopologyGraphNode, isAnchor: Bool, isHovered: Bool) -> Color {
        if isAnchor { return .accentColor }
        if node.issueCount > 0 { return Color.orange.opacity(0.7) }
        if node.health.needsAttention { return node.health.topologyTint.opacity(0.7) }
        return .primary.opacity(isHovered ? 0.35 : 0.15)
    }
}
