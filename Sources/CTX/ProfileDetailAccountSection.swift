import CTXCore
import SwiftUI

extension ProfileDetailView {
    var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACCOUNT")
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(sectionHeaderStyle)
                .tracking(1.1)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ProfileDetailResponsiveRow(label: profile.accountLabel) {
                    HStack(spacing: 6) {
                        Text(profile.accountID.isEmpty ? "-" : profile.accountID)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .textSelection(.enabled)
                        if !profile.accountID.isEmpty {
                            copyButton(for: profile.accountID, fieldName: "account")
                        }
                    }
                }

                if !profile.region.isEmpty {
                    Divider()
                        .padding(.leading, 16)
                    ProfileDetailResponsiveRow(label: profile.regionLabel) {
                        Text(profile.region)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                }

                if !profile.roleName.isEmpty || profile.provider == .aws {
                    Divider()
                        .padding(.leading, 16)
                    ProfileDetailResponsiveRow(label: profile.roleLabel) {
                        if availableRoles.count > 1 {
                            AWSRoleMenu(roles: availableRoles, currentRole: profile.roleName) { newRole in
                                roleUpdateError = store.updateAWSRole(
                                    for: profile,
                                    roleName: newRole,
                                    targetFolder: store.folder(for: profile),
                                    from: .mainWindow
                                ) ?? ""
                            }
                        } else {
                            HStack(spacing: 6) {
                                Text(profile.roleName.isEmpty ? "-" : profile.roleName)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                    .textSelection(.enabled)
                                if !profile.roleName.isEmpty {
                                    copyButton(for: profile.roleName, fieldName: "role")
                                }
                            }
                        }
                    }
                }

                if profile.provider == .aws && !profile.ssoStartURL.isEmpty {
                    Divider()
                        .padding(.leading, 16)
                    ProfileDetailResponsiveRow(label: "SSO Start URL") {
                        Text(profile.ssoStartURL)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .fontWeight(.medium)
                            .textSelection(.enabled)
                    }
                }

                if profile.provider == .aws && !profile.ssoRegion.isEmpty {
                    Divider()
                        .padding(.leading, 16)
                    ProfileDetailResponsiveRow(label: "SSO Region") {
                        Text(profile.ssoRegion)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                }
            }
            .ctxGlassCard()

            if !roleUpdateError.isEmpty {
                Label(roleUpdateError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Role update failed: \(roleUpdateError)")
            }
        }
    }
}
