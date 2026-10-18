import AppKit
import SwiftUI
import CTXCore

struct ClusterFinOpsRecommendationSheet: View {
    let rec: FinOpsRecommendation
    let formatCurrency: (Double) -> String
    let onDismiss: () -> Void

    @State private var copiedYAML = false
    @State private var copiedVerifyCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(rec.title)
                            .font(.title3.weight(.bold))

                        Text(rec.riskLevel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                    Text(rec.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            // Financial Summary Strip
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT REQUEST")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(rec.currentAllocation)
                        .font(.callout.weight(.medium))
                }

                Divider().frame(height: 35)

                VStack(alignment: .leading, spacing: 4) {
                    Text("RECOMMENDED TARGET")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(rec.suggestedAllocation)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.green)
                }

                Divider().frame(height: 35)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ESTIMATED MONTHLY SAVINGS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(formatCurrency(rec.monthlySavingsUSD)) / month")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            // Safety Guardrail Callout
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safety Guardrails Applied")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(rec.safetyHeadroom) · Request is adjusted to fit actual consumption while container limits remain intact to eliminate CPU throttling and OOMKills.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            // Step 1: Verification Command
            if let verifyCmd = rec.verificationCommand {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Verify Live Pod Consumption in Terminal")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(verifyCmd)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(verifyCmd, forType: .string)
                            copiedVerifyCommand = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedVerifyCommand = false
                            }
                        } label: {
                            Label(copiedVerifyCommand ? "Copied!" : "Copy", systemImage: copiedVerifyCommand ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Step 2: YAML Patch Snippet
            if let yaml = rec.yamlPatchSnippet {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("2. Suggested Resource Patch (YAML)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(yaml, forType: .string)
                            copiedYAML = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedYAML = false
                            }
                        } label: {
                            Label(copiedYAML ? "Copied!" : "Copy YAML", systemImage: copiedYAML ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                        }
                    }

                    Text(yaml)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 600, height: 500)
    }
}
