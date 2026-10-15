import CTXCore
import SwiftUI

// MARK: - Tech Brand Icon Component

struct TechBrandIconView: View, Equatable {
    let name: String

    static func == (lhs: TechBrandIconView, rhs: TechBrandIconView) -> Bool {
        lhs.name == rhs.name
    }

    static func brand(for name: String) -> (icon: String, color: Color) {
        let lower = name.lowercased()
        if lower.contains("redis") { return ("cylinder.fill", .red) }
        if lower.contains("postgre") || lower.contains("sql") || lower.contains("db") || lower.contains("mongo") { return ("database.fill", .blue) }
        if lower.contains("nginx") || lower.contains("ingress") || lower.contains("front") || lower.contains("web") { return ("network", .green) }
        if lower.contains("kafka") || lower.contains("event") || lower.contains("mq") || lower.contains("pub") { return ("bolt.horizontal.fill", .orange) }
        if lower.contains("argo") || lower.contains("flux") || lower.contains("gitops") || lower.contains("deploy") { return ("arrow.triangle.pull", .indigo) }
        if lower.contains("prom") || lower.contains("graf") || lower.contains("metric") || lower.contains("monitor") { return ("chart.xyaxis.line", .orange) }
        if lower.contains("auth") || lower.contains("sec") || lower.contains("key") { return ("lock.shield.fill", .purple) }
        if lower.contains("pay") || lower.contains("bill") || lower.contains("checkout") { return ("creditcard.fill", .mint) }
        if lower.contains("api") || lower.contains("service") || lower.contains("app") { return ("gearshape.fill", .cyan) }
        return ("cube.fill", .blue)
    }

    var body: some View {
        let brand = Self.brand(for: name)
        return HStack(spacing: 4) {
            Image(systemName: brand.icon)
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(brand.color)
            Text(name)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(brand.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(brand.color.opacity(0.3), lineWidth: 1)
        }
    }
}



// MARK: - Authentic Kubernetes & Cloud Vector SVG Icons

/// Native SwiftUI vector shapes and path generators for Kubernetes objects,
/// cloud providers, and architecture components matching industry-standard
/// tools (k8sight, CNCF, SimpleIcons).
public enum KubernetesVectorIcon: String, CaseIterable, Sendable {
    case pod
    case deployment
    case statefulSet
    case daemonSet
    case replicaSet
    case job
    case cronJob
    case service
    case ingress
    case networkPolicy
    case configMap
    case secret
    case persistentVolume
    case persistentVolumeClaim
    case storageClass
    case serviceAccount
    case role
    case clusterRole
    case roleBinding
    case hpa
    case helm
    case aws
    case azure
    case gcp
    case kubernetes
    case cluster
    case topology
    case costs
    case cpu
    case memory
    case box

    public init(nodeKind: TopologyGraphNodeKind) {
        switch nodeKind {
        case .pod, .podGroup, .terminalGroup, .overflow:
            self = .pod
        case .deployment, .workload:
            self = .deployment
        case .statefulSet:
            self = .statefulSet
        case .daemonSet:
            self = .daemonSet
        case .replicaSet:
            self = .replicaSet
        case .job:
            self = .job
        case .cronJob:
            self = .cronJob
        case .service:
            self = .service
        case .ingress:
            self = .ingress
        case .networkPolicy:
            self = .networkPolicy
        case .configMap:
            self = .configMap
        case .secret:
            self = .secret
        case .pv:
            self = .persistentVolume
        case .pvc:
            self = .persistentVolumeClaim
        case .storageClass:
            self = .storageClass
        case .serviceAccount:
            self = .serviceAccount
        case .role, .clusterRole:
            self = .role
        case .roleBinding:
            self = .roleBinding
        case .hpa:
            self = .hpa
        }
    }

    public init(category: TopologyNodeCategory) {
        switch category {
        case .workload: self = .deployment
        case .network: self = .service
        case .storage: self = .persistentVolumeClaim
        case .config: self = .configMap
        case .rbac: self = .role
        }
    }

    public var systemImageFallback: String {
        switch self {
        case .pod: return "shippingbox"
        case .deployment: return "square.stack.3d.up"
        case .statefulSet: return "server.rack"
        case .daemonSet: return "arrow.triangle.2.circlepath"
        case .replicaSet: return "square.grid.2x2"
        case .job: return "hammer"
        case .cronJob: return "clock"
        case .service: return "network"
        case .ingress: return "arrow.triangle.pull"
        case .networkPolicy: return "shield.lefthalf.filled"
        case .configMap: return "doc.badge.gearshape"
        case .secret: return "key"
        case .persistentVolume, .persistentVolumeClaim: return "internaldrive"
        case .storageClass: return "externaldrive.badge.icloud"
        case .serviceAccount: return "person.crop.circle"
        case .role, .clusterRole, .roleBinding: return "lock"
        case .hpa: return "arrow.up.and.down.square"
        case .helm, .kubernetes, .cluster: return "helm"
        case .aws: return "cloud"
        case .azure: return "cloud.fill"
        case .gcp: return "cloud.sun"
        case .topology: return "point.3.connected.trianglepath.dotted"
        case .costs: return "dollarsign.circle"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .box: return "cube"
        }
    }

    /// Generates a resolution-independent vector `Path` scaled and centered into `rect`.
    public func path(in rect: CGRect) -> Path {
        let unscaled = unscaled24Path
        let scale = min(rect.width / 24.0, rect.height / 24.0)
        let offsetX = rect.minX + (rect.width - 24.0 * scale) / 2.0
        let offsetY = rect.minY + (rect.height - 24.0 * scale) / 2.0

        let transform = CGAffineTransform(translationX: offsetX, y: offsetY)
            .scaledBy(x: scale, y: scale)
        return unscaled.applying(transform)
    }

    /// Renders the vector icon directly into a SwiftUI GraphicsContext.
    public func draw(in context: GraphicsContext, rect: CGRect, color: Color, lineWidth: CGFloat = 1.6) {
        let p = path(in: rect)
        switch self {
        case .azure:
            context.fill(p, with: .color(color))
        default:
            context.stroke(
                p,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: - 24x24 Base Coordinate Paths matching k8sight / CNCF specs

    private var unscaled24Path: Path {
        var path = Path()
        switch self {
        case .pod:
            // Isometric 3D Hexagonal Pod Box
            path.move(to: CGPoint(x: 21, y: 16))
            path.addLine(to: CGPoint(x: 21, y: 8))
            path.addQuadCurve(to: CGPoint(x: 20, y: 6.27), control: CGPoint(x: 21, y: 6.8))
            path.addLine(to: CGPoint(x: 13, y: 2.27))
            path.addQuadCurve(to: CGPoint(x: 11, y: 2.27), control: CGPoint(x: 12, y: 1.7))
            path.addLine(to: CGPoint(x: 4, y: 6.27))
            path.addQuadCurve(to: CGPoint(x: 3, y: 8), control: CGPoint(x: 3, y: 6.8))
            path.addLine(to: CGPoint(x: 3, y: 16))
            path.addQuadCurve(to: CGPoint(x: 4, y: 17.73), control: CGPoint(x: 3, y: 17.2))
            path.addLine(to: CGPoint(x: 11, y: 21.73))
            path.addQuadCurve(to: CGPoint(x: 13, y: 21.73), control: CGPoint(x: 12, y: 22.3))
            path.addLine(to: CGPoint(x: 20, y: 17.73))
            path.addQuadCurve(to: CGPoint(x: 21, y: 16), control: CGPoint(x: 21, y: 17.2))
            path.closeSubpath()

            path.move(to: CGPoint(x: 3.3, y: 7))
            path.addLine(to: CGPoint(x: 12, y: 12))
            path.addLine(to: CGPoint(x: 20.7, y: 7))

            path.move(to: CGPoint(x: 12, y: 22))
            path.addLine(to: CGPoint(x: 12, y: 12))

        case .deployment:
            // 3 stacked isometric planes
            path.move(to: CGPoint(x: 12, y: 2))
            path.addLine(to: CGPoint(x: 2, y: 7))
            path.addLine(to: CGPoint(x: 12, y: 12))
            path.addLine(to: CGPoint(x: 22, y: 7))
            path.closeSubpath()

            path.move(to: CGPoint(x: 2, y: 17))
            path.addLine(to: CGPoint(x: 12, y: 22))
            path.addLine(to: CGPoint(x: 22, y: 17))

            path.move(to: CGPoint(x: 2, y: 12))
            path.addLine(to: CGPoint(x: 12, y: 17))
            path.addLine(to: CGPoint(x: 22, y: 12))

        case .statefulSet:
            // Stacked database cylinders
            path.addEllipse(in: CGRect(x: 3, y: 2, width: 18, height: 6))
            path.move(to: CGPoint(x: 21, y: 12))
            path.addCurve(to: CGPoint(x: 3, y: 12),
                          control1: CGPoint(x: 17, y: 15),
                          control2: CGPoint(x: 7, y: 15))
            path.move(to: CGPoint(x: 3, y: 5))
            path.addLine(to: CGPoint(x: 3, y: 19))
            path.addCurve(to: CGPoint(x: 21, y: 19),
                          control1: CGPoint(x: 7, y: 22),
                          control2: CGPoint(x: 17, y: 22))
            path.addLine(to: CGPoint(x: 21, y: 5))

        case .daemonSet:
            // Circular loop arrows
            path.move(to: CGPoint(x: 17, y: 2))
            path.addLine(to: CGPoint(x: 21, y: 6))
            path.addLine(to: CGPoint(x: 17, y: 10))

            path.move(to: CGPoint(x: 3, y: 11))
            path.addLine(to: CGPoint(x: 3, y: 10))
            path.addCurve(to: CGPoint(x: 7, y: 6), control1: CGPoint(x: 3, y: 7.8), control2: CGPoint(x: 4.8, y: 6))
            path.addLine(to: CGPoint(x: 21, y: 6))

            path.move(to: CGPoint(x: 7, y: 22))
            path.addLine(to: CGPoint(x: 3, y: 18))
            path.addLine(to: CGPoint(x: 7, y: 14))

            path.move(to: CGPoint(x: 21, y: 13))
            path.addLine(to: CGPoint(x: 21, y: 14))
            path.addCurve(to: CGPoint(x: 17, y: 18), control1: CGPoint(x: 21, y: 16.2), control2: CGPoint(x: 19.2, y: 18))
            path.addLine(to: CGPoint(x: 3, y: 18))

        case .replicaSet:
            // Stacked duplicate boxes
            path.addRoundedRect(in: CGRect(x: 9, y: 9, width: 13, height: 13), cornerSize: CGSize(width: 2, height: 2))
            path.move(to: CGPoint(x: 5, y: 15))
            path.addLine(to: CGPoint(x: 4, y: 15))
            path.addCurve(to: CGPoint(x: 2, y: 13), control1: CGPoint(x: 2.9, y: 15), control2: CGPoint(x: 2, y: 14.1))
            path.addLine(to: CGPoint(x: 2, y: 4))
            path.addCurve(to: CGPoint(x: 4, y: 2), control1: CGPoint(x: 2, y: 2.9), control2: CGPoint(x: 2.9, y: 2))
            path.addLine(to: CGPoint(x: 13, y: 2))
            path.addCurve(to: CGPoint(x: 15, y: 4), control1: CGPoint(x: 14.1, y: 2), control2: CGPoint(x: 15, y: 2.9))
            path.addLine(to: CGPoint(x: 15, y: 5))

        case .job:
            path.addRoundedRect(in: CGRect(x: 2, y: 7, width: 20, height: 14), cornerSize: CGSize(width: 2, height: 2))
            path.move(to: CGPoint(x: 16, y: 21))
            path.addLine(to: CGPoint(x: 16, y: 5))
            path.addCurve(to: CGPoint(x: 14, y: 3), control1: CGPoint(x: 16, y: 3.9), control2: CGPoint(x: 15.1, y: 3))
            path.addLine(to: CGPoint(x: 10, y: 3))
            path.addCurve(to: CGPoint(x: 8, y: 5), control1: CGPoint(x: 8.9, y: 3), control2: CGPoint(x: 8, y: 3.9))
            path.addLine(to: CGPoint(x: 8, y: 21))

        case .cronJob:
            path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
            path.move(to: CGPoint(x: 12, y: 6))
            path.addLine(to: CGPoint(x: 12, y: 12))
            path.addLine(to: CGPoint(x: 16, y: 14))

        case .service:
            path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
            path.move(to: CGPoint(x: 2, y: 12))
            path.addLine(to: CGPoint(x: 22, y: 12))
            path.addEllipse(in: CGRect(x: 6.5, y: 2, width: 11, height: 20))

        case .ingress:
            path.move(to: CGPoint(x: 15, y: 3))
            path.addLine(to: CGPoint(x: 19, y: 3))
            path.addCurve(to: CGPoint(x: 21, y: 5), control1: CGPoint(x: 20.1, y: 3), control2: CGPoint(x: 21, y: 3.9))
            path.addLine(to: CGPoint(x: 21, y: 19))
            path.addCurve(to: CGPoint(x: 19, y: 21), control1: CGPoint(x: 21, y: 20.1), control2: CGPoint(x: 20.1, y: 21))
            path.addLine(to: CGPoint(x: 15, y: 21))

            path.move(to: CGPoint(x: 10, y: 17))
            path.addLine(to: CGPoint(x: 15, y: 12))
            path.addLine(to: CGPoint(x: 10, y: 7))

            path.move(to: CGPoint(x: 15, y: 12))
            path.addLine(to: CGPoint(x: 3, y: 12))

        case .networkPolicy:
            path.move(to: CGPoint(x: 12, y: 22))
            path.addCurve(to: CGPoint(x: 20, y: 12), control1: CGPoint(x: 16, y: 20), control2: CGPoint(x: 20, y: 16))
            path.addLine(to: CGPoint(x: 20, y: 5))
            path.addLine(to: CGPoint(x: 12, y: 2))
            path.addLine(to: CGPoint(x: 4, y: 5))
            path.addLine(to: CGPoint(x: 4, y: 12))
            path.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 4, y: 16), control2: CGPoint(x: 8, y: 20))
            path.closeSubpath()

            path.move(to: CGPoint(x: 9, y: 12))
            path.addLine(to: CGPoint(x: 11, y: 14))
            path.addLine(to: CGPoint(x: 15, y: 10))

        case .configMap:
            path.move(to: CGPoint(x: 4, y: 21)); path.addLine(to: CGPoint(x: 4, y: 14))
            path.move(to: CGPoint(x: 4, y: 10)); path.addLine(to: CGPoint(x: 4, y: 3))
            path.move(to: CGPoint(x: 12, y: 21)); path.addLine(to: CGPoint(x: 12, y: 12))
            path.move(to: CGPoint(x: 12, y: 8)); path.addLine(to: CGPoint(x: 12, y: 3))
            path.move(to: CGPoint(x: 20, y: 21)); path.addLine(to: CGPoint(x: 20, y: 16))
            path.move(to: CGPoint(x: 20, y: 12)); path.addLine(to: CGPoint(x: 20, y: 3))

            path.move(to: CGPoint(x: 1, y: 14)); path.addLine(to: CGPoint(x: 7, y: 14))
            path.move(to: CGPoint(x: 9, y: 8)); path.addLine(to: CGPoint(x: 15, y: 8))
            path.move(to: CGPoint(x: 17, y: 16)); path.addLine(to: CGPoint(x: 23, y: 16))

        case .secret:
            path.addEllipse(in: CGRect(x: 2, y: 10, width: 11, height: 11))
            path.move(to: CGPoint(x: 21, y: 2))
            path.addLine(to: CGPoint(x: 11.4, y: 11.6))
            path.move(to: CGPoint(x: 15.5, y: 7.5))
            path.addLine(to: CGPoint(x: 18.5, y: 10.5))
            path.move(to: CGPoint(x: 22, y: 7))
            path.addLine(to: CGPoint(x: 19, y: 4))

        case .persistentVolume:
            path.move(to: CGPoint(x: 22, y: 12)); path.addLine(to: CGPoint(x: 2, y: 12))
            path.move(to: CGPoint(x: 5.5, y: 5.1))
            path.addLine(to: CGPoint(x: 2, y: 12))
            path.addLine(to: CGPoint(x: 2, y: 18))
            path.addCurve(to: CGPoint(x: 4, y: 20), control1: CGPoint(x: 2, y: 19.1), control2: CGPoint(x: 2.9, y: 20))
            path.addLine(to: CGPoint(x: 20, y: 20))
            path.addCurve(to: CGPoint(x: 22, y: 18), control1: CGPoint(x: 21.1, y: 20), control2: CGPoint(x: 22, y: 19.1))
            path.addLine(to: CGPoint(x: 22, y: 12))
            path.addLine(to: CGPoint(x: 18.5, y: 5.1))
            path.addCurve(to: CGPoint(x: 16.8, y: 4), control1: CGPoint(x: 18.2, y: 4.4), control2: CGPoint(x: 17.5, y: 4))
            path.addLine(to: CGPoint(x: 7.2, y: 4))
            path.addCurve(to: CGPoint(x: 5.5, y: 5.1), control1: CGPoint(x: 6.5, y: 4), control2: CGPoint(x: 5.8, y: 4.4))
            path.closeSubpath()

            path.move(to: CGPoint(x: 6, y: 16)); path.addLine(to: CGPoint(x: 6.01, y: 16))
            path.move(to: CGPoint(x: 10, y: 16)); path.addLine(to: CGPoint(x: 10.01, y: 16))

        case .persistentVolumeClaim:
            path.move(to: CGPoint(x: 22, y: 19))
            path.addCurve(to: CGPoint(x: 20, y: 21), control1: CGPoint(x: 22, y: 20.1), control2: CGPoint(x: 21.1, y: 21))
            path.addLine(to: CGPoint(x: 4, y: 21))
            path.addCurve(to: CGPoint(x: 2, y: 19), control1: CGPoint(x: 2.9, y: 21), control2: CGPoint(x: 2, y: 20.1))
            path.addLine(to: CGPoint(x: 2, y: 5))
            path.addCurve(to: CGPoint(x: 4, y: 3), control1: CGPoint(x: 2, y: 3.9), control2: CGPoint(x: 2.9, y: 3))
            path.addLine(to: CGPoint(x: 9, y: 3))
            path.addLine(to: CGPoint(x: 11, y: 6))
            path.addLine(to: CGPoint(x: 20, y: 6))
            path.addCurve(to: CGPoint(x: 22, y: 8), control1: CGPoint(x: 21.1, y: 6), control2: CGPoint(x: 22, y: 6.9))
            path.closeSubpath()

        case .storageClass:
            path.move(to: CGPoint(x: 12, y: 2))
            path.addLine(to: CGPoint(x: 2, y: 7))
            path.addLine(to: CGPoint(x: 12, y: 12))
            path.addLine(to: CGPoint(x: 22, y: 7))
            path.closeSubpath()

            path.move(to: CGPoint(x: 2, y: 17))
            path.addLine(to: CGPoint(x: 12, y: 22))
            path.addLine(to: CGPoint(x: 22, y: 17))

            path.move(to: CGPoint(x: 2, y: 12))
            path.addLine(to: CGPoint(x: 12, y: 17))
            path.addLine(to: CGPoint(x: 22, y: 12))

        case .serviceAccount:
            path.move(to: CGPoint(x: 17, y: 21))
            path.addLine(to: CGPoint(x: 17, y: 19))
            path.addCurve(to: CGPoint(x: 13, y: 15), control1: CGPoint(x: 17, y: 16.8), control2: CGPoint(x: 15.2, y: 15))
            path.addLine(to: CGPoint(x: 5, y: 15))
            path.addCurve(to: CGPoint(x: 1, y: 19), control1: CGPoint(x: 2.8, y: 15), control2: CGPoint(x: 1, y: 16.8))
            path.addLine(to: CGPoint(x: 1, y: 21))

            path.addEllipse(in: CGRect(x: 5, y: 3, width: 8, height: 8))

            path.move(to: CGPoint(x: 23, y: 21))
            path.addLine(to: CGPoint(x: 23, y: 19))
            path.addCurve(to: CGPoint(x: 20, y: 15.13), control1: CGPoint(x: 23, y: 17.1), control2: CGPoint(x: 21.7, y: 15.5))
            path.move(to: CGPoint(x: 16, y: 3.13))
            path.addCurve(to: CGPoint(x: 16, y: 10.88), control1: CGPoint(x: 18.5, y: 4.5), control2: CGPoint(x: 18.5, y: 9.5))

        case .role, .clusterRole, .roleBinding:
            path.addRoundedRect(in: CGRect(x: 3, y: 11, width: 18, height: 11), cornerSize: CGSize(width: 2, height: 2))
            path.move(to: CGPoint(x: 7, y: 11))
            path.addLine(to: CGPoint(x: 7, y: 7))
            path.addCurve(to: CGPoint(x: 17, y: 7), control1: CGPoint(x: 7, y: 3.5), control2: CGPoint(x: 17, y: 3.5))
            path.addLine(to: CGPoint(x: 17, y: 11))

        case .hpa:
            path.addRoundedRect(in: CGRect(x: 3, y: 3, width: 18, height: 18), cornerSize: CGSize(width: 3, height: 3))
            path.move(to: CGPoint(x: 12, y: 7)); path.addLine(to: CGPoint(x: 12, y: 17))
            path.move(to: CGPoint(x: 9, y: 10)); path.addLine(to: CGPoint(x: 12, y: 7)); path.addLine(to: CGPoint(x: 15, y: 10))
            path.move(to: CGPoint(x: 9, y: 14)); path.addLine(to: CGPoint(x: 12, y: 17)); path.addLine(to: CGPoint(x: 15, y: 14))

        case .helm:
            // Authentic CNCF Nautical Ship Wheel / Helm
            path.addEllipse(in: CGRect(x: 4.8, y: 4.8, width: 14.4, height: 14.4))
            path.addEllipse(in: CGRect(x: 6.8, y: 6.8, width: 10.4, height: 10.4))
            path.addEllipse(in: CGRect(x: 10.0, y: 10.0, width: 4.0, height: 4.0))

            let center = CGPoint(x: 12, y: 12)
            let spokeStartR: CGFloat = 2.0
            let spokeEndR: CGFloat = 5.2
            let handleStartR: CGFloat = 7.2
            let handleEndR: CGFloat = 11.2

            for i in 0..<8 {
                let angle = CGFloat(i) * (.pi / 4.0)
                let cosA = cos(angle)
                let sinA = sin(angle)
                path.move(to: CGPoint(x: center.x + spokeStartR * cosA, y: center.y + spokeStartR * sinA))
                path.addLine(to: CGPoint(x: center.x + spokeEndR * cosA, y: center.y + spokeEndR * sinA))
                path.move(to: CGPoint(x: center.x + handleStartR * cosA, y: center.y + handleStartR * sinA))
                path.addLine(to: CGPoint(x: center.x + handleEndR * cosA, y: center.y + handleEndR * sinA))
            }

        case .kubernetes, .cluster:
            path.addEllipse(in: CGRect(x: 4, y: 4, width: 16, height: 16))
            path.addEllipse(in: CGRect(x: 10, y: 10, width: 4, height: 4))
            path.move(to: CGPoint(x: 12, y: 2)); path.addLine(to: CGPoint(x: 12, y: 9.5))
            path.move(to: CGPoint(x: 19, y: 5)); path.addLine(to: CGPoint(x: 13.8, y: 10.2))
            path.move(to: CGPoint(x: 22, y: 12)); path.addLine(to: CGPoint(x: 14.5, y: 12))
            path.move(to: CGPoint(x: 19, y: 19)); path.addLine(to: CGPoint(x: 13.8, y: 13.8))
            path.move(to: CGPoint(x: 12, y: 14.5)); path.addLine(to: CGPoint(x: 12, y: 22))
            path.move(to: CGPoint(x: 10.2, y: 13.8)); path.addLine(to: CGPoint(x: 5, y: 19))
            path.move(to: CGPoint(x: 9.5, y: 12)); path.addLine(to: CGPoint(x: 2, y: 12))
            path.move(to: CGPoint(x: 10.2, y: 10.2)); path.addLine(to: CGPoint(x: 5, y: 5))

        case .topology:
            path.addEllipse(in: CGRect(x: 15, y: 2, width: 6, height: 6))
            path.addEllipse(in: CGRect(x: 3, y: 9, width: 6, height: 6))
            path.addEllipse(in: CGRect(x: 15, y: 16, width: 6, height: 6))
            path.move(to: CGPoint(x: 8.6, y: 13.5))
            path.addLine(to: CGPoint(x: 15.4, y: 17.5))
            path.move(to: CGPoint(x: 8.6, y: 10.5))
            path.addLine(to: CGPoint(x: 15.4, y: 6.5))

        case .costs:
            path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            path.move(to: CGPoint(x: 16, y: 8.5))
            path.addLine(to: CGPoint(x: 10.8, y: 8.5))
            path.addCurve(to: CGPoint(x: 10.8, y: 13.1), control1: CGPoint(x: 8.5, y: 8.5), control2: CGPoint(x: 8.5, y: 13.1))
            path.addLine(to: CGPoint(x: 13.2, y: 13.1))
            path.addCurve(to: CGPoint(x: 13.2, y: 17.7), control1: CGPoint(x: 15.5, y: 13.1), control2: CGPoint(x: 15.5, y: 17.7))
            path.addLine(to: CGPoint(x: 8, y: 17.7))
            path.move(to: CGPoint(x: 12, y: 6)); path.addLine(to: CGPoint(x: 12, y: 8))
            path.move(to: CGPoint(x: 12, y: 18)); path.addLine(to: CGPoint(x: 12, y: 20))

        case .cpu:
            path.addRoundedRect(in: CGRect(x: 4, y: 4, width: 16, height: 16), cornerSize: CGSize(width: 2, height: 2))
            path.addRect(CGRect(x: 9, y: 9, width: 6, height: 6))
            path.move(to: CGPoint(x: 9, y: 1)); path.addLine(to: CGPoint(x: 9, y: 4))
            path.move(to: CGPoint(x: 15, y: 1)); path.addLine(to: CGPoint(x: 15, y: 4))
            path.move(to: CGPoint(x: 9, y: 20)); path.addLine(to: CGPoint(x: 9, y: 23))
            path.move(to: CGPoint(x: 15, y: 20)); path.addLine(to: CGPoint(x: 15, y: 23))
            path.move(to: CGPoint(x: 1, y: 9)); path.addLine(to: CGPoint(x: 4, y: 9))
            path.move(to: CGPoint(x: 1, y: 15)); path.addLine(to: CGPoint(x: 4, y: 15))
            path.move(to: CGPoint(x: 20, y: 9)); path.addLine(to: CGPoint(x: 23, y: 9))
            path.move(to: CGPoint(x: 20, y: 15)); path.addLine(to: CGPoint(x: 23, y: 15))

        case .memory:
            path.addRoundedRect(in: CGRect(x: 3, y: 8, width: 18, height: 10), cornerSize: CGSize(width: 1, height: 1))
            path.move(to: CGPoint(x: 7, y: 8)); path.addLine(to: CGPoint(x: 7, y: 6))
            path.move(to: CGPoint(x: 12, y: 8)); path.addLine(to: CGPoint(x: 12, y: 6))
            path.move(to: CGPoint(x: 17, y: 8)); path.addLine(to: CGPoint(x: 17, y: 6))
            path.move(to: CGPoint(x: 6, y: 12)); path.addLine(to: CGPoint(x: 6, y: 14))
            path.move(to: CGPoint(x: 10, y: 12)); path.addLine(to: CGPoint(x: 10, y: 14))
            path.move(to: CGPoint(x: 14, y: 12)); path.addLine(to: CGPoint(x: 14, y: 14))
            path.move(to: CGPoint(x: 18, y: 12)); path.addLine(to: CGPoint(x: 18, y: 14))

        case .aws:
            path.move(to: CGPoint(x: 6.5, y: 19))
            path.addCurve(to: CGPoint(x: 5.95, y: 10.03), control1: CGPoint(x: 4.0, y: 19), control2: CGPoint(x: 3.5, y: 14.5))
            path.addCurve(to: CGPoint(x: 17.7, y: 9.16), control1: CGPoint(x: 7.5, y: 6), control2: CGPoint(x: 15.5, y: 5))
            path.addCurve(to: CGPoint(x: 17.5, y: 19), control1: CGPoint(x: 21, y: 11), control2: CGPoint(x: 21, y: 19))
            path.closeSubpath()
            path.move(to: CGPoint(x: 12, y: 16.5)); path.addLine(to: CGPoint(x: 12, y: 11.7))
            path.move(to: CGPoint(x: 9.7, y: 13.4)); path.addLine(to: CGPoint(x: 12, y: 11.1)); path.addLine(to: CGPoint(x: 14.3, y: 13.4))

        case .azure:
            path.move(to: CGPoint(x: 13.05, y: 4.24))
            path.addLine(to: CGPoint(x: 8.55, y: 12.03))
            path.addLine(to: CGPoint(x: 11.97, y: 17.95))
            path.addLine(to: CGPoint(x: 2.5, y: 17.95))
            path.addLine(to: CGPoint(x: 7.0, y: 10.16))
            path.addLine(to: CGPoint(x: 10.43, y: 4.24))
            path.closeSubpath()

            path.move(to: CGPoint(x: 14.45, y: 4.24))
            path.addLine(to: CGPoint(x: 21.5, y: 4.24))
            path.addLine(to: CGPoint(x: 14.47, y: 18.0))
            path.addLine(to: CGPoint(x: 7.42, y: 18.0))
            path.closeSubpath()

        case .gcp:
            path.move(to: CGPoint(x: 19.35, y: 10.04))
            path.addCurve(to: CGPoint(x: 12, y: 4), control1: CGPoint(x: 18.67, y: 6.59), control2: CGPoint(x: 15.64, y: 4))
            path.addCurve(to: CGPoint(x: 5.63, y: 8.81), control1: CGPoint(x: 9.11, y: 4), control2: CGPoint(x: 6.64, y: 6.08))
            path.addCurve(to: CGPoint(x: 2, y: 14), control1: CGPoint(x: 3.52, y: 9.97), control2: CGPoint(x: 2, y: 11.83))
            path.addCurve(to: CGPoint(x: 8, y: 20), control1: CGPoint(x: 2, y: 17.31), control2: CGPoint(x: 4.69, y: 20))
            path.addLine(to: CGPoint(x: 19, y: 20))
            path.addCurve(to: CGPoint(x: 22, y: 15), control1: CGPoint(x: 20.66, y: 20), control2: CGPoint(x: 22, y: 17.76))
            path.addCurve(to: CGPoint(x: 19.35, y: 10.04), control1: CGPoint(x: 22, y: 12.38), control2: CGPoint(x: 20.85, y: 10.28))
            path.closeSubpath()

        case .box:
            path.addRoundedRect(in: CGRect(x: 3, y: 3, width: 18, height: 18), cornerSize: CGSize(width: 3, height: 3))
        }
        return path
    }
}

// MARK: - SwiftUI Icon View Component

public struct KubernetesIconView: View {
    public let icon: KubernetesVectorIcon
    public var size: CGFloat = 18
    public var tint: Color = .blue
    public var filledBackground: Bool = true

    public init(icon: KubernetesVectorIcon, size: CGFloat = 18, tint: Color = .blue, filledBackground: Bool = true) {
        self.icon = icon
        self.size = size
        self.tint = tint
        self.filledBackground = filledBackground
    }

    public init(nodeKind: TopologyGraphNodeKind, size: CGFloat = 18, tint: Color? = nil, filledBackground: Bool = true) {
        self.icon = KubernetesVectorIcon(nodeKind: nodeKind)
        self.size = size
        self.tint = tint ?? Color(hex: nodeKind.defaultHexColor)
        self.filledBackground = filledBackground
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            icon.draw(in: context, rect: rect, color: tint, lineWidth: max(1.2, size * 0.08))
        }
        .frame(width: size, height: size)
        .padding(filledBackground ? 5 : 0)
        .background(
            filledBackground
                ? RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.14))
                : nil
        )
        .overlay(
            filledBackground
                ? RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
                : nil
        )
    }
}

// MARK: - Color Hex Initializer

extension Color {
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
