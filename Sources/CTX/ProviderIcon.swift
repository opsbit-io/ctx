import CTXCore
import SwiftUI

/// Renders a cloud provider's official logo from the app bundle, falling back
/// to a monochrome SF Symbol when the image asset isn't present.
///
/// Drop the official logo files into `Sources/CTX/Resources/` named exactly:
///   aws.svg · gcp.svg · azure.svg · kubernetes.svg
struct ProviderIcon: View {
    let provider: CloudProvider
    /// Tint used only for the SF Symbol fallback (logos keep their own colors).
    var fallbackTint: Color? = nil
    @ScaledMetric private var size: CGFloat

    init(provider: CloudProvider, size: CGFloat = 18, fallbackTint: Color? = nil) {
        self.provider = provider
        self.fallbackTint = fallbackTint
        self._size = ScaledMetric(wrappedValue: size)
    }

    private var assetName: String {
        switch provider {
        case .aws: "aws"
        case .gcp: "gcp"
        case .azure: "azure"
        case .kubernetes: "kubernetes"
        }
    }

    @ViewBuilder
    var body: some View {
        // We use Bundle.safeModule exclusively to prevent Bundle.module crashes
        // when the compiled app runs outside standard SwiftPM environment contexts.
        if let bundle = Bundle.safeModule,
           let url = bundle.url(forResource: assetName, withExtension: "svg"),
           let nsImage = NSImage(contentsOf: url) {
            // Force NSImage to render at target vector size to ensure pixel-perfect Retina sharpness.
            let _ = { nsImage.size = NSSize(width: size, height: size) }()
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: provider.systemImage + ".fill")
                .font(.system(size: size))
                .foregroundStyle(fallbackTint ?? .secondary)
        }
    }
}

extension Bundle {
    static var safeModule: Bundle? {
        // 1. Look for the resource bundle inside the main bundle's Resources directory (macOS app standard)
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("CTX_CTX.bundle"),
           let bundle = Bundle(url: bundleURL) {
            return bundle
        }
        // 2. Look for it directly inside the main bundle (flat)
        if let bundleURL = Bundle.main.bundleURL.appendingPathComponent("CTX_CTX.bundle") as URL?,
           let bundle = Bundle(url: bundleURL) {
            return bundle
        }
        // 3. Look for it relative to the executable (command line tool style)
        if let execURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("CTX_CTX.bundle"),
           let bundle = Bundle(url: execURL) {
            return bundle
        }
        // 4. Fallback: try to locate the bundle relative to the Swift build directory
        //    Works on any machine regardless of username or project path.
        if let execURL = Bundle.main.executableURL {
            // .build/<arch>/debug or .build/<arch>/release sibling to the executable
            let archDir = execURL.deletingLastPathComponent()
            for bundleName in ["CTX_CTX.bundle"] {
                let candidate = archDir.appendingPathComponent(bundleName)
                if let bundle = Bundle(url: candidate) {
                    return bundle
                }
            }
        }
        return nil
    }
}

/// Modular Retina-sharp SVG Brand Icon renderer shared across Cloud Providers,
/// Helm, ArgoCD, Flux CD, and Flagger.
struct CTXBrandSVGIcon: View {
    let assetName: String
    let fallbackSystemImage: String
    var fallbackTint: Color = .secondary
    @ScaledMetric private var size: CGFloat

    init(
        assetName: String,
        size: CGFloat = 18,
        fallbackSystemImage: String = "shippingbox.fill",
        fallbackTint: Color = .secondary
    ) {
        self.assetName = assetName
        self.fallbackSystemImage = fallbackSystemImage
        self.fallbackTint = fallbackTint
        self._size = ScaledMetric(wrappedValue: size)
    }

    var body: some View {
        let image: NSImage? = {
            if let bundle = Bundle.safeModule,
               let url = bundle.url(forResource: assetName, withExtension: "svg"),
               let img = NSImage(contentsOf: url) {
                return img
            }
            if let directImg = NSImage(contentsOfFile: "Sources/CTX/Resources/\(assetName).svg") {
                return directImg
            }
            return nil
        }()

        if let nsImage = image {
            let _ = { nsImage.size = NSSize(width: size, height: size) }()
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSystemImage)
                .font(.system(size: size * 0.82, weight: .semibold))
                .foregroundStyle(fallbackTint)
                .frame(width: size, height: size)
        }
    }
}

/// Official CNCF GitOps Brand Icon for ArgoCD (`argocd.svg`), Flux CD (`flux.svg`), and Flagger (`flagger.svg`).
struct GitOpsBrandIconView: View {
    let provider: String
    var size: CGFloat = 18

    var body: some View {
        let brand = CTXBrandIconResolver.resolve(for: provider)
        CTXBrandSVGIcon(
            assetName: brand.svgAsset ?? "kubernetes",
            size: size,
            fallbackSystemImage: brand.fallbackSymbol,
            fallbackTint: brand.fallbackTint
        )
    }
}

// MARK: - Unified Brand & DevOps Icon Resolver

public enum CTXBrandIconResolver {
    public struct ResolvedBrand: Sendable {
        public let svgAsset: String?
        public let fallbackSymbol: String
        public let fallbackTint: Color

        public init(svgAsset: String?, fallbackSymbol: String, fallbackTint: Color) {
            self.svgAsset = svgAsset
            self.fallbackSymbol = fallbackSymbol
            self.fallbackTint = fallbackTint
        }
    }

    public static func resolve(for name: String) -> ResolvedBrand {
        let lower = name.lowercased()

        // 1. LLM & AI Frameworks
        if lower.contains("langfuse") {
            return ResolvedBrand(svgAsset: "langfuse", fallbackSymbol: "brain.head.profile", fallbackTint: Color(red: 0.04, green: 0.38, blue: 0.71))
        }
        if lower.contains("openai") || lower.contains("gpt") {
            return ResolvedBrand(svgAsset: "openai", fallbackSymbol: "sparkles", fallbackTint: Color(red: 0.25, green: 0.16, blue: 0.57))
        }
        if lower.contains("anthropic") || lower.contains("claude") {
            return ResolvedBrand(svgAsset: "anthropic", fallbackSymbol: "atom", fallbackTint: Color(red: 0.85, green: 0.47, blue: 0.34))
        }
        if lower.contains("hugging") || lower.contains("transformers") {
            return ResolvedBrand(svgAsset: "huggingface", fallbackSymbol: "face.smiling.fill", fallbackTint: Color(red: 1.0, green: 0.82, blue: 0.12))
        }
        if lower.contains("qdrant") {
            return ResolvedBrand(svgAsset: "qdrant", fallbackSymbol: "cube.transparent.fill", fallbackTint: .red)
        }
        if lower.contains("ollama") {
            return ResolvedBrand(svgAsset: "ollama", fallbackSymbol: "cpu.fill", fallbackTint: .primary)
        }

        // 2. GitOps & Progressive Delivery
        if lower.contains("argo") {
            return ResolvedBrand(svgAsset: "argocd", fallbackSymbol: "arrow.triangle.branch", fallbackTint: .orange)
        }
        if lower.contains("flux") {
            return ResolvedBrand(svgAsset: "flux", fallbackSymbol: "bolt.horizontal.circle.fill", fallbackTint: .cyan)
        }
        if lower.contains("flagger") {
            return ResolvedBrand(svgAsset: "flagger", fallbackSymbol: "flag.checkered", fallbackTint: .purple)
        }
        if lower.contains("helm") {
            return ResolvedBrand(svgAsset: "helm", fallbackSymbol: "helm", fallbackTint: .indigo)
        }

        // 3. Databases & Data Stores
        if lower.contains("redis") || lower.contains("valkey") {
            return ResolvedBrand(svgAsset: "redis", fallbackSymbol: "cylinder.fill", fallbackTint: .red)
        }
        if lower.contains("postgre") || lower.contains("pgsql") {
            return ResolvedBrand(svgAsset: "postgres", fallbackSymbol: "externaldrive.fill", fallbackTint: .blue)
        }
        if lower.contains("mysql") || lower.contains("mariadb") {
            return ResolvedBrand(svgAsset: "mysql", fallbackSymbol: "externaldrive.fill", fallbackTint: .teal)
        }
        if lower.contains("mongo") {
            return ResolvedBrand(svgAsset: "mongodb", fallbackSymbol: "leaf.fill", fallbackTint: .green)
        }
        if lower.contains("elastic") || lower.contains("opensearch") {
            return ResolvedBrand(svgAsset: "elasticsearch", fallbackSymbol: "magnifyingglass.circle.fill", fallbackTint: .mint)
        }
        if lower.contains("clickhouse") {
            return ResolvedBrand(svgAsset: "clickhouse", fallbackSymbol: "chart.bar.xaxis", fallbackTint: .yellow)
        }
        if lower.contains("supabase") {
            return ResolvedBrand(svgAsset: "supabase", fallbackSymbol: "bolt.fill", fallbackTint: .green)
        }

        // 4. Queues & Event Streaming
        if lower.contains("kafka") {
            return ResolvedBrand(svgAsset: "kafka", fallbackSymbol: "point.3.connected.trianglepath.dotted", fallbackTint: .orange)
        }
        if lower.contains("rabbit") {
            return ResolvedBrand(svgAsset: "rabbitmq", fallbackSymbol: "hare.fill", fallbackTint: .orange)
        }

        // 5. Gateways & Ingress
        if lower.contains("nginx") {
            return ResolvedBrand(svgAsset: "nginx", fallbackSymbol: "network", fallbackTint: .green)
        }
        if lower.contains("istio") {
            return ResolvedBrand(svgAsset: "istio", fallbackSymbol: "sailboat.fill", fallbackTint: .blue)
        }
        if lower.contains("traefik") {
            return ResolvedBrand(svgAsset: "traefik", fallbackSymbol: "arrow.triangle.swap", fallbackTint: Color(red: 0.14, green: 0.63, blue: 0.76))
        }
        if lower.contains("cilium") {
            return ResolvedBrand(svgAsset: "cilium", fallbackSymbol: "point.3.filled.connected.trianglepath.dotted", fallbackTint: Color(red: 0.95, green: 0.50, blue: 0.17))
        }

        // 6. Security, Identity & Compliance
        if lower.contains("okta") {
            return ResolvedBrand(svgAsset: "okta", fallbackSymbol: "lock.circle.fill", fallbackTint: Color(red: 0.0, green: 0.49, blue: 0.76))
        }
        if lower.contains("vault") {
            return ResolvedBrand(svgAsset: "vault", fallbackSymbol: "lock.square.fill", fallbackTint: .yellow)
        }
        if lower.contains("wiz") {
            return ResolvedBrand(svgAsset: "wiz", fallbackSymbol: "shield.checkered", fallbackTint: Color(red: 0.02, green: 0.33, blue: 0.92))
        }
        if lower.contains("sonar") {
            return ResolvedBrand(svgAsset: "sonarqube", fallbackSymbol: "waveform.path.ecg", fallbackTint: .cyan)
        }
        if lower.contains("zscaler") {
            return ResolvedBrand(svgAsset: "zscaler", fallbackSymbol: "network.badge.shield.half.filled", fallbackTint: Color(red: 0.15, green: 0.42, blue: 0.97))
        }
        if lower.contains("slack") {
            return ResolvedBrand(svgAsset: "slack", fallbackSymbol: "bubble.left.and.bubble.right.fill", fallbackTint: Color(red: 0.88, green: 0.12, blue: 0.35))
        }
        if lower.contains("nvidia") || lower.contains("gpu") {
            return ResolvedBrand(svgAsset: "nvidia", fallbackSymbol: "memorychip.fill", fallbackTint: Color(red: 0.46, green: 0.73, blue: 0.0))
        }

        // 7. Observability & Telemetry
        if lower.contains("prom") {
            return ResolvedBrand(svgAsset: "prometheus", fallbackSymbol: "flame.fill", fallbackTint: .orange)
        }
        if lower.contains("graf") {
            return ResolvedBrand(svgAsset: "grafana", fallbackSymbol: "chart.xyaxis.line", fallbackTint: .orange)
        }
        if lower.contains("loki") {
            return ResolvedBrand(svgAsset: "loki", fallbackSymbol: "doc.text.magnifyingglass", fallbackTint: .orange)
        }
        if lower.contains("jaeger") {
            return ResolvedBrand(svgAsset: "jaeger", fallbackSymbol: "waveform.path", fallbackTint: .cyan)
        }
        if lower.contains("datadog") {
            return ResolvedBrand(svgAsset: "datadog", fallbackSymbol: "pawprint.fill", fallbackTint: .purple)
        }
        if lower.contains("otel") || lower.contains("telemetry") {
            return ResolvedBrand(svgAsset: "opentelemetry", fallbackSymbol: "dot.radiowaves.up.forward", fallbackTint: .indigo)
        }
        if lower.contains("sentry") {
            return ResolvedBrand(svgAsset: "sentry", fallbackSymbol: "exclamationmark.bubble.fill", fallbackTint: Color(red: 0.21, green: 0.18, blue: 0.35))
        }
        if lower.contains("pagerduty") {
            return ResolvedBrand(svgAsset: "pagerduty", fallbackSymbol: "bell.badge.fill", fallbackTint: Color(red: 0.02, green: 0.67, blue: 0.22))
        }
        if lower.contains("newrelic") {
            return ResolvedBrand(svgAsset: "newrelic", fallbackSymbol: "chart.line.uptrend.xyaxis", fallbackTint: Color(red: 0.11, green: 0.91, blue: 0.51))
        }

        // 8. CI/CD, Registry & Storage
        if lower.contains("docker") {
            return ResolvedBrand(svgAsset: "docker", fallbackSymbol: "shippingbox.fill", fallbackTint: .blue)
        }
        if lower.contains("artifactory") {
            return ResolvedBrand(svgAsset: "artifactory", fallbackSymbol: "shippingbox.circle.fill", fallbackTint: .green)
        }
        if lower.contains("harbor") {
            return ResolvedBrand(svgAsset: "harbor", fallbackSymbol: "lifepreserver.fill", fallbackTint: Color(red: 0.38, green: 0.73, blue: 0.20))
        }
        if lower.contains("git") {
            if lower.contains("gitlab") {
                return ResolvedBrand(svgAsset: "gitlab", fallbackSymbol: "chevron.left.forwardslash.chevron.right", fallbackTint: .orange)
            }
            return ResolvedBrand(svgAsset: "github", fallbackSymbol: "chevron.left.forwardslash.chevron.right", fallbackTint: .primary)
        }
        if lower.contains("terra") {
            return ResolvedBrand(svgAsset: "terraform", fallbackSymbol: "square.stack.3d.up.fill", fallbackTint: .purple)
        }
        if lower.contains("ansible") {
            return ResolvedBrand(svgAsset: "ansible", fallbackSymbol: "terminal.fill", fallbackTint: .red)
        }
        if lower.contains("minio") || lower.contains("s3") {
            return ResolvedBrand(svgAsset: "minio", fallbackSymbol: "cylinder.split.1x2.fill", fallbackTint: .red)
        }

        // Generic category fallbacks
        if lower.contains("sql") || lower.contains("db") {
            return ResolvedBrand(svgAsset: nil, fallbackSymbol: "database.fill", fallbackTint: .blue)
        }
        if lower.contains("ingress") || lower.contains("router") || lower.contains("proxy") {
            return ResolvedBrand(svgAsset: nil, fallbackSymbol: "network", fallbackTint: .green)
        }
        if lower.contains("auth") || lower.contains("sec") || lower.contains("key") {
            return ResolvedBrand(svgAsset: nil, fallbackSymbol: "lock.shield.fill", fallbackTint: .purple)
        }
        if lower.contains("pay") || lower.contains("bill") || lower.contains("checkout") {
            return ResolvedBrand(svgAsset: nil, fallbackSymbol: "creditcard.fill", fallbackTint: .mint)
        }
        if lower.contains("api") || lower.contains("service") || lower.contains("gateway") {
            return ResolvedBrand(svgAsset: nil, fallbackSymbol: "gearshape.fill", fallbackTint: .cyan)
        }

        return ResolvedBrand(svgAsset: nil, fallbackSymbol: "cube.fill", fallbackTint: .blue)
    }
}
