import CTXCore
import SwiftUI

struct TopologyInspectorDetailView: View {
    let node: TopologyGraphNode

    private var rows: [(String, String)] {
        let cells = node.row.cells
        let candidates: [(String, String?)]
        switch node.kind {
        case .ingress:
            candidates = [
                ("Hosts", cells["Hosts"]), ("TLS", cells["TLS"]),
                ("Class", cells["Class"]), ("Age", cells["Age"])
            ]
        case .service:
            candidates = [
                ("Type", cells["Type"]), ("Cluster IP", cells["Cluster IP"]),
                ("External", cells["External"]), ("Ports", cells["Ports"]),
                ("Selector", cells["Selector"]), ("Age", cells["Age"])
            ]
        case .workload, .deployment, .statefulSet, .daemonSet, .replicaSet, .job, .cronJob:
            candidates = [
                ("Kind", cells["Kind"]), ("Ready", cells["Ready"]),
                ("Available", cells["Available"]), ("Image", cells["Image"]),
                ("Selector", cells["Selector"]), ("Age", cells["Age"])
            ]
        case .pod:
            candidates = [
                ("Status", cells["Status"]), ("Ready", cells["Ready"]),
                ("Restarts", cells["Restarts"]), ("CPU", cells["CPU"]),
                ("Memory", cells["Memory"]), ("QoS", cells["QoS"]),
                ("Pod IP", cells["Pod IP"]), ("Node", cells["Node"]),
                ("Owner", cells["Owner"]), ("Image", cells["Image"]),
                ("Age", cells["Age"])
            ]
        case .pvc, .pv, .storageClass:
            candidates = [
                ("Status", cells["Status"]), ("Capacity", cells["Capacity"]),
                ("Storage class", cells["StorageClass"]), ("Access modes", cells["Access Modes"]),
                ("Volume", cells["Volume"]), ("Age", cells["Age"])
            ]
        case .configMap, .secret:
            candidates = [
                ("Data", cells["Data"] ?? cells["Keys"]), ("Age", cells["Age"])
            ]
        case .networkPolicy:
            candidates = [
                ("Pod selector", cells["PodSelector"]), ("Types", cells["PolicyTypes"]), ("Age", cells["Age"])
            ]
        case .serviceAccount, .role, .clusterRole, .roleBinding:
            candidates = [
                ("Subjects", cells["Subjects"]), ("Role", cells["Role"]), ("Age", cells["Age"])
            ]
        case .hpa:
            candidates = [
                ("Scales", cells["Reference"]), ("Replicas now", cells["Replicas"]),
                ("Minimum", cells["MinPods"]), ("Maximum", cells["MaxPods"]),
                ("Age", cells["Age"])
            ]
        case .podGroup, .terminalGroup, .overflow:
            candidates = []
        }
        return candidates.compactMap { title, value in
            guard let value, !value.isEmpty, value != "-" else { return nil }
            return (title, value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TopologyInspectorSectionTitle(text: "DETAILS")
            if rows.isEmpty {
                Text("No additional details for this object.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows, id: \.0) { title, value in
                    HStack(alignment: .top, spacing: 8) {
                        Text(title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 86, alignment: .leading)
                        Text(value)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct TopologyInspectorSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}
