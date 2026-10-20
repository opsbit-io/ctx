import SwiftUI

extension ProfileDetailView {
    var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DIAGNOSTICS")
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(sectionHeaderStyle)
                .tracking(1.1)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ProfileDetailResponsiveRow(label: "Last Login") {
                    Text(formatted(store.lastLoginAt))
                        .fontWeight(.medium)
                }

                Divider()
                    .padding(.leading, 16)

                ProfileDetailResponsiveRow(label: "Last Verification") {
                    Text(formatted(store.lastVerifiedAt))
                        .fontWeight(.medium)
                }

                Divider()
                    .padding(.leading, 16)

                ProfileDetailResponsiveRow(label: "Last Call Duration") {
                    Text(duration(store.lastCommandDuration))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
            }
            .ctxGlassCard()
        }
    }
}
