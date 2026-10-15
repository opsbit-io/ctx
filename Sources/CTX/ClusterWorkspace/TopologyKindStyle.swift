import CTXCore
import SwiftUI

extension TopologyGraphNodeKind {
    public var topologyTint: Color {
        Color(hex: defaultHexColor)
    }
}

extension TopologyNodeHealthState {
    public var topologyTint: Color {
        if isFailed { return Color(hex: "#f85149") } // Red
        if isDegraded { return Color(hex: "#d29922") } // Amber
        if isIdle { return Color.secondary }
        return Color(hex: "#3fb950") // Green
    }
}
