import Foundation

/// High-level domain category for grouping and quick-filtering graph nodes.
public enum TopologyNodeCategory: String, Sendable, Codable, CaseIterable {
    case workload = "Workloads"
    case network = "Network"
    case storage = "Storage"
    case config = "Config"
    case rbac = "RBAC"

    public var title: String { rawValue }

    public var defaultHexColor: String {
        switch self {
        case .workload: return "#326CE5"
        case .network: return "#00B4D8"
        case .storage: return "#E76F51"
        case .config: return "#2A9D8F"
        case .rbac: return "#9B5DE5"
        }
    }
}

/// The map's data model: a real directed graph of Kubernetes objects, not a
/// bundle of pre-bucketed lists.
public enum TopologyGraphNodeKind: String, Sendable, Codable, CaseIterable {
    case ingress
    case service
    case workload
    case deployment
    case statefulSet
    case daemonSet
    case cronJob
    case job
    case replicaSet
    case pod
    /// Several interchangeable healthy pods drawn as one node.
    case podGroup
    /// Successfully completed pods hidden from the active runtime path.
    case terminalGroup
    /// Additional siblings hidden by a projection budget or parent cap.
    case overflow
    case pvc
    case pv
    case storageClass
    case configMap
    case secret
    case networkPolicy
    case serviceAccount
    case role
    case clusterRole
    case roleBinding
    case hpa

    /// High-level category for toolbar pills filtering.
    public var category: TopologyNodeCategory {
        switch self {
        case .workload, .deployment, .statefulSet, .daemonSet, .cronJob, .job, .replicaSet,
             .pod, .podGroup, .terminalGroup, .overflow, .hpa:
            return .workload
        case .ingress, .service, .networkPolicy:
            return .network
        case .pvc, .pv, .storageClass:
            return .storage
        case .configMap, .secret:
            return .config
        case .serviceAccount, .role, .clusterRole, .roleBinding:
            return .rbac
        }
    }

    public var defaultHexColor: String {
        switch self {
        case .workload, .deployment, .statefulSet, .daemonSet, .cronJob, .job, .replicaSet,
             .pod, .podGroup, .terminalGroup, .overflow, .hpa:
            return "#326CE5"
        case .ingress, .service, .networkPolicy:
            return "#00B4D8"
        case .pvc, .pv, .storageClass:
            return "#E76F51"
        case .configMap, .secret:
            return "#2A9D8F"
        case .serviceAccount, .role, .clusterRole, .roleBinding:
            return "#9B5DE5"
        }
    }

    /// The column this kind sits in. Lineage flows left to right:
    /// entrypoint → routing → controller → runtime → storage.
    public var layerFloor: Int {
        switch self {
        case .ingress, .hpa: 0
        case .service, .networkPolicy: 1
        case .workload, .deployment, .statefulSet, .daemonSet, .cronJob, .job, .replicaSet: 2
        case .pod, .podGroup, .terminalGroup, .overflow: 3
        case .pvc, .pv, .storageClass, .configMap, .secret, .serviceAccount, .role, .clusterRole, .roleBinding: 4
        }
    }

    public var title: String {
        switch self {
        case .ingress: "Ingress"
        case .service: "Service"
        case .workload: "Workload"
        case .deployment: "Deployment"
        case .statefulSet: "StatefulSet"
        case .daemonSet: "DaemonSet"
        case .cronJob: "CronJob"
        case .job: "Job"
        case .replicaSet: "ReplicaSet"
        case .pod: "Pod"
        case .podGroup: "Pods"
        case .terminalGroup: "Completed Pods"
        case .overflow: "More"
        case .pvc: "PersistentVolumeClaim"
        case .pv: "PersistentVolume"
        case .storageClass: "StorageClass"
        case .configMap: "ConfigMap"
        case .secret: "Secret"
        case .networkPolicy: "NetworkPolicy"
        case .serviceAccount: "ServiceAccount"
        case .role: "Role"
        case .clusterRole: "ClusterRole"
        case .roleBinding: "RoleBinding"
        case .hpa: "HorizontalPodAutoscaler"
        }
    }

    public var systemImage: String {
        switch self {
        case .ingress: "arrow.triangle.branch"
        case .service: "point.3.connected.trianglepath.dotted"
        case .workload, .deployment: "shippingbox"
        case .statefulSet: "server.rack"
        case .daemonSet: "gearshape.2"
        case .cronJob, .job: "clock.arrow.2.circlepath"
        case .replicaSet: "square.grid.2x2"
        case .pod, .podGroup: "circle.grid.3x3"
        case .terminalGroup: "checkmark.circle"
        case .overflow: "ellipsis.circle"
        case .pvc, .pv: "internaldrive"
        case .storageClass: "externaldrive"
        case .configMap: "doc.text"
        case .secret: "key"
        case .networkPolicy: "shield"
        case .serviceAccount, .role, .clusterRole, .roleBinding: "person.badge.key"
        case .hpa: "arrow.up.and.down.square"
        }
    }

    /// Three-letter chip shown on the node.
    public var code: String {
        switch self {
        case .ingress: "ING"
        case .service: "SVC"
        case .workload: "WKL"
        case .deployment: "DEP"
        case .statefulSet: "STS"
        case .daemonSet: "DS"
        case .cronJob: "CRON"
        case .job: "JOB"
        case .replicaSet: "RS"
        case .pod: "POD"
        case .podGroup: "PODS"
        case .terminalGroup: "DONE"
        case .overflow: "MORE"
        case .pvc: "PVC"
        case .pv: "PV"
        case .storageClass: "SC"
        case .configMap: "CM"
        case .secret: "SEC"
        case .networkPolicy: "NET"
        case .serviceAccount: "SA"
        case .role: "ROL"
        case .clusterRole: "CROL"
        case .roleBinding: "RB"
        case .hpa: "HPA"
        }
    }
}

public struct TopologyGraphNode: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: TopologyGraphNodeKind
    public let name: String
    public let namespace: String
    /// The one line under the name — real state, never a guessed category.
    public let subtitle: String
    public let health: TopologyNodeHealthState
    public let row: KubernetesResourceRow
    public let issueCount: Int

    public init(
        id: String,
        kind: TopologyGraphNodeKind,
        name: String,
        namespace: String,
        subtitle: String,
        health: TopologyNodeHealthState,
        row: KubernetesResourceRow,
        issueCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.namespace = namespace
        self.subtitle = subtitle
        self.health = health
        self.row = row
        self.issueCount = issueCount
    }

    public var effectiveKind: TopologyGraphNodeKind {
        if kind == .workload {
            let k = (row.cells["Kind"] ?? "").lowercased()
            if k.contains("deploy") { return .deployment }
            if k.contains("stateful") { return .statefulSet }
            if k.contains("daemon") { return .daemonSet }
            if k.contains("cron") { return .cronJob }
            if k.contains("job") { return .job }
            if k.contains("replica") { return .replicaSet }
        }
        return kind
    }

    public var category: TopologyNodeCategory {
        effectiveKind.category
    }

    public static func == (lhs: TopologyGraphNode, rhs: TopologyGraphNode) -> Bool {
        lhs.id == rhs.id && lhs.health == rhs.health && lhs.issueCount == rhs.issueCount
    }

    public static func id(kind: TopologyGraphNodeKind, rowID: String) -> String {
        "\(kind.rawValue)/\(rowID)"
    }
}

/// Why two objects are connected.
public enum TopologyGraphEdgeKind: String, Sendable, CaseIterable {
    case routes
    case targets
    case selects
    case owns
    case mounts
    case scales

    public var defaultHexColor: String {
        switch self {
        case .routes: return "#e3b341"
        case .targets, .selects: return "#d29922"
        case .owns: return "#6e7681"
        case .mounts: return "#db6d28"
        case .scales: return "#326CE5"
        }
    }

    public var label: String {
        switch self {
        case .routes: "routes to"
        case .targets: "fronts"
        case .selects: "selects"
        case .owns: "manages"
        case .mounts: "mounts"
        case .scales: "scales"
        }
    }
}

public struct TopologyGraphEdge: Identifiable, Hashable, Sendable {
    public var id: String { "\(source)|\(target)|\(kind.rawValue)" }
    public let source: String
    public let target: String
    public let kind: TopologyGraphEdgeKind

    public init(source: String, target: String, kind: TopologyGraphEdgeKind) {
        self.source = source
        self.target = target
        self.kind = kind
    }
}

public struct ClusterTopologyGraph: Sendable {
    public let nodes: [TopologyGraphNode]
    public let edges: [TopologyGraphEdge]

    private let nodesByID: [String: TopologyGraphNode]
    private let outgoing: [String: [TopologyGraphEdge]]
    private let incoming: [String: [TopologyGraphEdge]]

    public var isEmpty: Bool { nodes.isEmpty }

    public init(nodes: [TopologyGraphNode], edges: [TopologyGraphEdge]) {
        var seenNodes = Set<String>()
        var uniqueNodes: [TopologyGraphNode] = []
        for node in nodes where !seenNodes.contains(node.id) {
            seenNodes.insert(node.id)
            uniqueNodes.append(node)
        }
        var seenEdges = Set<String>()
        var uniqueEdges: [TopologyGraphEdge] = []
        for edge in edges {
            guard seenNodes.contains(edge.source), seenNodes.contains(edge.target) else { continue }
            guard edge.source != edge.target, !seenEdges.contains(edge.id) else { continue }
            seenEdges.insert(edge.id)
            uniqueEdges.append(edge)
        }

        self.nodes = uniqueNodes
        self.edges = uniqueEdges
        self.nodesByID = Dictionary(uniqueKeysWithValues: uniqueNodes.map { ($0.id, $0) } )
        self.outgoing = Dictionary(grouping: uniqueEdges, by: \.source)
        self.incoming = Dictionary(grouping: uniqueEdges, by: \.target)
    }

    public func node(_ id: String) -> TopologyGraphNode? { nodesByID[id] }
    public func edgesOut(_ id: String) -> [TopologyGraphEdge] { outgoing[id] ?? [] }
    public func edgesIn(_ id: String) -> [TopologyGraphEdge] { incoming[id] ?? [] }

    public func lineage(of id: String) -> Set<String> {
        walk(from: id) { self.edgesOut($0).map(\.target) + self.edgesIn($0).map(\.source) }
    }

    public func ancestors(of id: String) -> Set<String> {
        walk(from: id) { self.edgesIn($0).map(\.source) }
    }

    public func descendants(of id: String) -> Set<String> {
        walk(from: id) { self.edgesOut($0).map(\.target) }
    }

    private func walk(from id: String, step: (String) -> [String]) -> Set<String> {
        var visited: Set<String> = [id]
        var queue = [id]
        while let current = queue.popLast() {
            for next in step(current) where !visited.contains(next) {
                visited.insert(next)
                queue.append(next)
            }
        }
        return visited
    }

    public func filtered(nodeIDs: Set<String>) -> ClusterTopologyGraph {
        ClusterTopologyGraph(
            nodes: nodes.filter { nodeIDs.contains($0.id) },
            edges: edges.filter { nodeIDs.contains($0.source) && nodeIDs.contains($0.target) }
        )
    }
}
