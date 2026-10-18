import SwiftUI
import CTXCore

struct ClusterFinOpsMethodologySheet: View {
    @ObservedObject var viewModel: ClusterWorkspaceViewModel
    @Binding var isPresented: Bool

    private var report: FinOpsReport {
        viewModel.currentFinOpsReport
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkerboard")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FinOps Methodology & Safety Guardrails")
                            .font(.title3.weight(.bold))
                        Text("Which values are live, which are modeled, and what CTX cannot verify")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !report.dataSource.isLiveAgent {
                    Button {
                        isPresented = false
                        viewModel.openOpenCostSetupWorkflow()
                    } label: {
                        Label(
                            viewModel.isFinOpsProviderDetected ? "Repair OpenCost…" : "Set up OpenCost…",
                            systemImage: "shield.lefthalf.filled.badge.checkmark"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    methodologySection(
                        icon: "dollarsign.circle.fill",
                        color: .blue,
                        title: "1. How Pricing is Calculated",
                        description: "CTX reads current Kubernetes requests, capacity and metrics from the selected context. It also discovers an existing OpenCost or Kubecost Service and reads its allocation API through the Kubernetes service proxy:",
                        bullets: [
                            "CTX does not ship hard-coded AWS, GCP or Azure rates.",
                            "CPU, memory and PVC quantities remain visible as live inventory even when pricing is unavailable.",
                            "When OpenCost or Kubecost is detected, displayed currency and history come from that provider.",
                            "Region, discounts, spot pricing, taxes, traffic and billing adjustments are never inferred from Kubernetes names."
                        ]
                    )

                    methodologySection(
                        icon: "arrow.down.right.and.arrow.up.left",
                        color: .green,
                        title: "2. What Right-Sizing Evidence Means",
                        description: "CTX does not generate right-sizing changes from a single current metrics snapshot. Safe recommendations require a representative historical demand source:",
                        bullets: [
                            "No recommendation is shown merely because current CPU usage is low.",
                            "Autoscaler policy, disruption budgets, bin-packing and workload peaks determine whether nodes can actually be removed.",
                            "Any future recommendation must identify its history window and pricing source."
                        ]
                    )

                    methodologySection(
                        icon: "lock.shield.fill",
                        color: .orange,
                        title: "3. Safety Boundaries",
                        description: "The FinOps workspace is advisory and cannot guarantee that a proposed request is safe for future traffic:",
                        bullets: [
                            "The 35% headroom is a calculation assumption, not proof of peak coverage.",
                            "CTX does not apply or patch resources from this inspection workflow.",
                            "Use long-term telemetry, load tests and your deployment process to validate changes.",
                            "Missing capacity, usage or pricing inputs stay missing rather than being replaced with invented cluster data."
                        ]
                    )
                }
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .padding(22)
        .frame(width: 620, height: 520)
    }

    private func methodologySection(icon: String, color: Color, title: String, description: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }

            Text(description)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(color)
                        Text(bullet)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
