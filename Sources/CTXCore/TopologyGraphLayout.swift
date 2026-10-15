import CoreGraphics
import Foundation

/// Layered ("Sugiyama") layout for the cluster map — placing objects in columns by
/// how far downstream they are, ordered within each column so the edges between
/// them cross as little as possible.
///
/// Three passes:
///   1. **Layering** — which column each node belongs to.
///   2. **Ordering** — the vertical order inside each column, by iterated
///      barycentre (average position of a node's neighbours in the adjacent
///      column).
///   3. **Coordinates** — turn the ordering into points.
public enum TopologyGraphLayout {
    public static let nodeWidth: CGFloat = 200
    public static let nodeHeight: CGFloat = 52
    public static let columnGap: CGFloat = 90
    public static let rowGap: CGFloat = 16
    public static let padding: CGFloat = 40

    public struct Result {
        public init() {}
        public var positions: [String: CGPoint] = [:]
        public var size: CGSize = .zero

        public func frame(_ id: String) -> CGRect? {
            positions[id].map { CGRect(x: $0.x, y: $0.y, width: nodeWidth, height: nodeHeight) }
        }

        /// The point an edge leaves from / arrives at: right edge of the source
        /// card, left edge of the target card, both vertically centred.
        public func anchors(from source: String, to target: String) -> (CGPoint, CGPoint)? {
            guard let a = frame(source), let b = frame(target) else { return nil }
            return (
                CGPoint(x: a.maxX, y: a.midY),
                CGPoint(x: b.minX, y: b.midY)
            )
        }
    }

    public static func layout(_ graph: ClusterTopologyGraph) -> Result {
        guard !graph.isEmpty else { return Result() }

        let ranks = assignRanks(graph)
        let ordered = orderLayers(graph, ranks: ranks)
        return assignCoordinates(ordered)
    }

    // MARK: - 1. Layering

    /// Each node sits at least in its kind's natural column and always to the right
    /// of everything pointing at it.
    private static func assignRanks(_ graph: ClusterTopologyGraph) -> [String: Int] {
        var ranks = graph.nodes.reduce(into: [String: Int]()) { $0[$1.id] = $1.kind.layerFloor }

        let maxPasses = min(graph.nodes.count, TopologyGraphNodeKind.allCases.count + 4)
        for _ in 0..<maxPasses {
            var changed = false
            for edge in graph.edges {
                guard let source = ranks[edge.source], let target = ranks[edge.target] else { continue }
                if target <= source {
                    ranks[edge.target] = source + 1
                    changed = true
                }
            }
            if !changed { break }
        }
        return ranks
    }

    // MARK: - 2. Crossing reduction

    private static func orderLayers(_ graph: ClusterTopologyGraph, ranks: [String: Int]) -> [[TopologyGraphNode]] {
        let maxRank = ranks.values.max() ?? 0
        var layers: [[TopologyGraphNode]] = Array(repeating: [], count: maxRank + 1)
        // Seed with a stable order (category, kind, then name) so an unchanged cluster
        // always lays out identically.
        for node in graph.nodes.sorted(by: { ($0.kind.category.rawValue, $0.kind.rawValue, $0.name) < ($1.kind.category.rawValue, $1.kind.rawValue, $1.name) }) {
            layers[ranks[node.id] ?? node.kind.layerFloor].append(node)
        }

        var index = positionIndex(layers)
        for pass in 0..<4 {
            let forward = pass % 2 == 0
            let range = forward ? Array(1..<layers.count) : Array((0..<max(layers.count - 1, 0)).reversed())
            for layerIndex in range {
                layers[layerIndex] = layers[layerIndex]
                    .map { node -> (TopologyGraphNode, Double) in
                        let neighbours = forward
                            ? graph.edgesIn(node.id).map(\.source)
                            : graph.edgesOut(node.id).map(\.target)
                        let known = neighbours.compactMap { index[$0] }
                        guard !known.isEmpty else {
                            return (node, Double(index[node.id] ?? 0))
                        }
                        return (node, known.reduce(0, +) / Double(known.count))
                    }
                    .sorted { ($0.1, $0.0.name) < ($1.1, $1.0.name) }
                    .map(\.0)
            }
            index = positionIndex(layers)
        }
        return layers
    }

    private static func positionIndex(_ layers: [[TopologyGraphNode]]) -> [String: Double] {
        var index: [String: Double] = [:]
        for layer in layers {
            for (position, node) in layer.enumerated() {
                index[node.id] = Double(position)
            }
        }
        return index
    }

    // MARK: - 3. Coordinates

    private static func assignCoordinates(_ layers: [[TopologyGraphNode]]) -> Result {
        var result = Result()
        let tallest = layers.map { CGFloat($0.count) * (nodeHeight + rowGap) }.max() ?? 0
        for (column, layer) in layers.enumerated() {
            let height = CGFloat(layer.count) * (nodeHeight + rowGap)
            let top = padding + (tallest - height) / 2
            let x = padding + CGFloat(column) * (nodeWidth + columnGap)
            for (row, node) in layer.enumerated() {
                result.positions[node.id] = CGPoint(x: x, y: top + CGFloat(row) * (nodeHeight + rowGap))
            }
        }

        result.size = CGSize(
            width: padding * 2 + CGFloat(max(layers.count, 1)) * nodeWidth + CGFloat(max(layers.count - 1, 0)) * columnGap,
            height: padding * 2 + tallest
        )
        return result
    }
}
