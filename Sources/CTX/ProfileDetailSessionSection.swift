import CTXCore
import SwiftUI

extension ProfileDetailView {
    var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SESSION")
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(sectionHeaderStyle)
                .tracking(1.1)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ProfileDetailResponsiveRow(label: "Connection") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connectionIsActive ? Color.green : currentProfile.status.color)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .fontWeight(.medium)
                    }
                }

                // The access token behind an SSO sign-in carries a refresh token and
                // renews silently, so its hourly expiry is not a deadline anyone acts
                // on. What governs CLI access from this machine is the credentials
                // already exported for this profile, and each profile has its own -
                // one connected an hour ago has an hour less than one connected now.
                if profile.provider == .aws,
                   let expiresAt = store.sessionExpiry(for: currentProfile),
                   expiresAt > Date() {
                    Divider()
                        .padding(.leading, 16)
                    ProfileDetailResponsiveRow(label: "Access expires in") {
                        SessionCountdownView(expiresAt: expiresAt)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }

                if connectionIsActive {
                    ForEach(store.connectionIdentityFields(for: currentProfile)) { field in
                        Divider()
                            .padding(.leading, 16)
                        ProfileDetailResponsiveRow(label: field.label) {
                            HStack(spacing: 6) {
                                Text(field.value)
                                    .fontWeight(.medium)
                                    .lineLimit(3)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .help(field.value)
                                copyButton(for: field.value, fieldName: field.label)
                            }
                        }
                    }
                } else {
                    Divider()
                        .padding(.leading, 16)
                    ProfileDetailResponsiveRow(label: "Identity") {
                        Text("Not Active")
                            .foregroundStyle(fieldLabelStyle)
                            .fontWeight(.medium)
                    }
                }
            }
            .ctxGlassCard()
        }
    }
}
