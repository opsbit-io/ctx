import CTXCore
import SwiftUI

/// A single column definition for `CTXResourceTable`. `key` must match a key in
/// `KubernetesResourceRow.cells`.
struct CTXTableColumn: Identifiable, Equatable {
    enum Alignment {
        case leading
        case trailing
    }

    var id: String { key }
    let key: String
    var title: String
    var minWidth: CGFloat
    var idealWidth: CGFloat
    var maxWidth: CGFloat
    var alignment: Alignment = .leading
    /// Higher priority survives longer when the table has to shed columns to fit a
    /// compact width. Ties keep their original left-to-right order.
    var priority: Int = 0
    var hideOnCompact: Bool = false
    var monospaced: Bool = false
    /// Exactly one column per kind should be `isFlexible` — it absorbs unused width
    /// on a wide window instead of the table leaving a dead strip of background,
    /// and shrinks first (down to `minWidth`) on a narrow one.
    var isFlexible: Bool = false
    /// Only set for values someone would actually copy elsewhere — a name, an IP, a
    /// hostname. Age/status/counts are read at a glance, never pasted anywhere, so an
    /// icon there is visual noise, not a convenience.
    var copyable: Bool = false

    static func text(_ key: String, min: CGFloat, ideal: CGFloat, max: CGFloat, priority: Int = 1, hideOnCompact: Bool = false, flexible: Bool = false, copyable: Bool = false) -> CTXTableColumn {
        CTXTableColumn(key: key, title: key, minWidth: min, idealWidth: ideal, maxWidth: max, priority: priority, hideOnCompact: hideOnCompact, isFlexible: flexible, copyable: copyable)
    }

    static func numeric(_ key: String, min: CGFloat, ideal: CGFloat, max: CGFloat, priority: Int = 1, hideOnCompact: Bool = false) -> CTXTableColumn {
        CTXTableColumn(key: key, title: key, minWidth: min, idealWidth: ideal, maxWidth: max, alignment: .trailing, priority: priority, hideOnCompact: hideOnCompact)
    }
}

/// Per-kind column definitions, providing balanced, human-friendly default widths
/// and responsive auto-scaling across all Kubernetes resource types.
///
/// Guaranteed:
/// - No column title ever truncates or clips to ellipsis (...) on initial load.
/// - Flexible columns (Name, Image) absorb extra space up to their sensible maxWidth.
/// - Trailing numeric columns have sufficient width for title + sort arrow + value.
enum CTXResourceColumns {
    static func columns(for kind: KubernetesResourceKind) -> [CTXTableColumn] {
        switch kind {
        case .namespaces:
            [
                .text("Name", min: 160, ideal: 320, max: 600, priority: 3, flexible: true, copyable: true),
                .text("Status", min: 85, ideal: 105, max: 130, priority: 2),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 2),
                .numeric("Labels", min: 70, ideal: 85, max: 110, priority: 1, hideOnCompact: true)
            ]
        case .nodes:
            [
                .text("Name", min: 160, ideal: 320, max: 600, priority: 3, flexible: true, copyable: true),
                .text("Ready", min: 72, ideal: 85, max: 110, priority: 3),
                .text("Roles", min: 80, ideal: 100, max: 140, priority: 2),
                .numeric("CPU Used", min: 80, ideal: 95, max: 120, priority: 3),
                .numeric("Memory Used", min: 95, ideal: 115, max: 140, priority: 3),
                .numeric("CPU", min: 80, ideal: 95, max: 120, priority: 1, hideOnCompact: true),
                .numeric("Memory", min: 90, ideal: 110, max: 140, priority: 1, hideOnCompact: true),
                .numeric("Disk", min: 85, ideal: 105, max: 130, priority: 1, hideOnCompact: true),
                .text("Version", min: 85, ideal: 105, max: 130, priority: 1, hideOnCompact: true),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 2),
                .text("IP", min: 110, ideal: 130, max: 170, priority: 1, hideOnCompact: true, copyable: true)
            ]
        case .workloads:
            [
                .text("Namespace", min: 120, ideal: 180, max: 320, priority: 2, copyable: true),
                .text("Kind", min: 85, ideal: 105, max: 140, priority: 2),
                .text("Name", min: 160, ideal: 280, max: 550, priority: 3, flexible: true, copyable: true),
                .text("Ready", min: 72, ideal: 85, max: 110, priority: 3),
                .numeric("Available", min: 85, ideal: 100, max: 130, priority: 1, hideOnCompact: true),
                .text("Image", min: 160, ideal: 280, max: 600, priority: 2, hideOnCompact: true, copyable: true),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 2)
            ]
        case .pods:
            [
                .text("Namespace", min: 120, ideal: 180, max: 320, priority: 2, copyable: true),
                .text("Name", min: 160, ideal: 280, max: 550, priority: 3, flexible: true, copyable: true),
                .text("Status", min: 90, ideal: 120, max: 160, priority: 3),
                .text("Ready", min: 72, ideal: 85, max: 110, priority: 2),
                .numeric("Restarts", min: 80, ideal: 95, max: 120, priority: 1, hideOnCompact: true),
                .numeric("CPU", min: 80, ideal: 95, max: 120, priority: 2),
                .numeric("Memory", min: 90, ideal: 110, max: 140, priority: 2),
                .text("Image", min: 160, ideal: 280, max: 600, priority: 2, hideOnCompact: true, copyable: true),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 2),
                .text("Node", min: 110, ideal: 150, max: 240, priority: 1, hideOnCompact: true)
            ]
        case .cronJobs:
            [
                .text("Namespace", min: 120, ideal: 180, max: 320, priority: 2, copyable: true),
                .text("Name", min: 160, ideal: 300, max: 600, priority: 3, flexible: true, copyable: true),
                .text("Schedule", min: 105, ideal: 135, max: 180, priority: 3, copyable: true),
                .text("Suspend", min: 75, ideal: 85, max: 110, priority: 1, hideOnCompact: true),
                .numeric("Active", min: 70, ideal: 80, max: 100, priority: 2),
                .text("Last Schedule", min: 115, ideal: 145, max: 200, priority: 2),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 2)
            ]
        case .services:
            [
                .text("Namespace", min: 120, ideal: 180, max: 320, priority: 2, copyable: true),
                .text("Name", min: 160, ideal: 300, max: 600, priority: 3, flexible: true, copyable: true),
                .text("Type", min: 85, ideal: 105, max: 140, priority: 2),
                .text("Cluster IP", min: 110, ideal: 135, max: 170, priority: 1, hideOnCompact: true, copyable: true),
                .text("External", min: 100, ideal: 130, max: 200, priority: 1, hideOnCompact: true, copyable: true),
                .text("Ports", min: 115, ideal: 175, max: 280, priority: 2, copyable: true),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 1, hideOnCompact: true)
            ]
        case .ingress:
            [
                .text("Namespace", min: 120, ideal: 180, max: 320, priority: 2, copyable: true),
                .text("Name", min: 160, ideal: 320, max: 650, priority: 3, flexible: true, copyable: true),
                .text("Class", min: 80, ideal: 95, max: 130, priority: 1, hideOnCompact: true),
                .text("Hosts", min: 135, ideal: 240, max: 480, priority: 2, copyable: true),
                .text("TLS", min: 65, ideal: 75, max: 95, priority: 1, hideOnCompact: true),
                .text("Address", min: 110, ideal: 180, max: 360, priority: 1, hideOnCompact: true, copyable: true),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 1, hideOnCompact: true)
            ]
        case .configMaps:
            [
                .text("Namespace", min: 120, ideal: 180, max: 320, priority: 2, copyable: true),
                .text("Name", min: 160, ideal: 320, max: 650, priority: 3, flexible: true, copyable: true),
                .numeric("Keys", min: 65, ideal: 80, max: 100, priority: 2),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 2)
            ]
        case .secretMetadata:
            [
                .text("Namespace", min: 120, ideal: 180, max: 320, priority: 2, copyable: true),
                .text("Name", min: 160, ideal: 320, max: 650, priority: 3, flexible: true, copyable: true),
                .text("Type", min: 120, ideal: 220, max: 380, priority: 1, hideOnCompact: true, copyable: true),
                .numeric("Keys", min: 65, ideal: 80, max: 100, priority: 2),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 2)
            ]
        case .events:
            [
                .text("Namespace", min: 120, ideal: 180, max: 320, priority: 2, copyable: true),
                .text("Object", min: 135, ideal: 240, max: 480, priority: 3, copyable: true),
                .text("Type", min: 80, ideal: 95, max: 120, priority: 2),
                .text("Reason", min: 105, ideal: 135, max: 180, priority: 2),
                .text("Message", min: 160, ideal: 340, max: 700, priority: 3, flexible: true, copyable: true),
                .text("Last", min: 65, ideal: 80, max: 100, priority: 1, hideOnCompact: true),
                .numeric("Count", min: 65, ideal: 80, max: 100, priority: 1, hideOnCompact: true)
            ]
        case .hpa:
            [
                .text("Namespace", min: 120, ideal: 180, max: 320, priority: 2, copyable: true),
                .text("Name", min: 160, ideal: 280, max: 550, priority: 3, flexible: true, copyable: true),
                .text("Reference", min: 120, ideal: 200, max: 360, priority: 2, copyable: true),
                .text("Targets", min: 105, ideal: 160, max: 280, priority: 2),
                .numeric("MinPods", min: 75, ideal: 85, max: 110, priority: 1, hideOnCompact: true),
                .numeric("MaxPods", min: 75, ideal: 85, max: 110, priority: 1, hideOnCompact: true),
                .numeric("Replicas", min: 75, ideal: 85, max: 110, priority: 3),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 2)
            ]
        case .pvc:
            [
                .text("Namespace", min: 120, ideal: 180, max: 320, priority: 2, copyable: true),
                .text("Name", min: 160, ideal: 280, max: 550, priority: 3, flexible: true, copyable: true),
                .text("Status", min: 85, ideal: 100, max: 130, priority: 3),
                .text("Volume", min: 125, ideal: 220, max: 380, priority: 2, copyable: true),
                .numeric("Capacity", min: 80, ideal: 95, max: 130, priority: 2),
                .text("Access Modes", min: 95, ideal: 125, max: 160, priority: 1, hideOnCompact: true),
                .text("StorageClass", min: 110, ideal: 150, max: 240, priority: 1, hideOnCompact: true),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 2)
            ]
        }
    }

    static func columns(for section: ClusterWorkspaceSection) -> [CTXTableColumn] {
        switch section {
        case .gitops:
            return [
                .text("Namespace", min: 120, ideal: 160, max: 280, priority: 2, copyable: true),
                .text("Name", min: 160, ideal: 240, max: 500, priority: 3, flexible: true, copyable: true),
                .text("Provider", min: 85, ideal: 100, max: 130, priority: 2),
                .text("Source", min: 85, ideal: 105, max: 140, priority: 1, hideOnCompact: true),
                .text("Status", min: 85, ideal: 105, max: 130, priority: 3),
                .text("Health", min: 85, ideal: 105, max: 140, priority: 2),
                .text("Repo URL", min: 140, ideal: 250, max: 550, priority: 1, hideOnCompact: true, copyable: true),
                .text("Target", min: 95, ideal: 130, max: 240, priority: 1, hideOnCompact: true, copyable: true),
                .text("Synced", min: 85, ideal: 110, max: 200, priority: 1, hideOnCompact: true, copyable: true),
                .numeric("Age", min: 65, ideal: 75, max: 95, priority: 2)
            ]
        case .helm:
            return [
                .text("Namespace", min: 120, ideal: 180, max: 320, priority: 2, copyable: true),
                .text("Name", min: 160, ideal: 280, max: 600, priority: 3, flexible: true, copyable: true),
                .text("Chart", min: 125, ideal: 220, max: 380, priority: 2, copyable: true),
                .text("App Version", min: 95, ideal: 115, max: 150, priority: 1, hideOnCompact: true),
                .numeric("Revision", min: 75, ideal: 85, max: 110, priority: 2),
                .text("Status", min: 85, ideal: 105, max: 130, priority: 3),
                .numeric("Updated", min: 75, ideal: 90, max: 120, priority: 2)
            ]
        default:
            if let kind = section.resourceKind {
                return columns(for: kind)
            }
            return columns(for: KubernetesResourceKind.pods)
        }
    }
}
