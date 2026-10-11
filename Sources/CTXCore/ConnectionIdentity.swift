import Foundation

public struct ConnectionIdentityField: Identifiable, Equatable, Sendable {
    public var id: String { label }
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

extension ProfileStore {
    public func connectionIdentityFields(for profile: CloudProfile) -> [ConnectionIdentityField] {
        let linkedProfile = profile.kubernetesLinkedProfile.flatMap { linkedName in
            profiles.first { $0.provider == .aws && $0.name == linkedName }
        }
        return ConnectionIdentityPresentation.fields(
            for: profile,
            linkedProfile: linkedProfile,
            resolvedIdentity: resolvedConnectionIdentities[profile.id]
        )
    }
}

public enum ConnectionIdentityPresentation {
    public static func fields(
        for profile: CloudProfile,
        linkedProfile: CloudProfile? = nil,
        resolvedIdentity: String? = nil
    ) -> [ConnectionIdentityField] {
        switch profile.provider {
        case .aws:
            return compactIdentityFields([
                ("AWS Profile", profile.name),
                ("Account ID", profile.accountID),
                ("Role", profile.roleName),
                ("Caller Identity", resolvedIdentity ?? "")
            ])
        case .gcp:
            return compactIdentityFields([
                ("GCP Configuration", profile.name),
                ("Project", profile.accountID),
                ("Signed-in Account", resolvedIdentity ?? profile.roleName)
            ])
        case .azure:
            return compactIdentityFields([
                ("Azure Subscription", profile.name),
                ("Subscription ID", profile.accountID),
                ("Tenant ID", profile.roleName),
                ("Signed-in Account", resolvedIdentity ?? "")
            ])
        case .kubernetes:
            var fields = compactIdentityFields([
                ("Kubernetes User", profile.roleName),
                ("Credential Type", credentialDescription(profile.kubernetesCredentialKind))
            ])
            if let aws = linkedProfile, aws.provider == .aws {
                fields.append(contentsOf: compactIdentityFields([
                    ("Auth Provider", "AWS EKS"),
                    ("AWS Profile", aws.name),
                    ("Account ID", aws.accountID),
                    ("Role", aws.roleName),
                    ("Caller Identity", resolvedIdentity ?? "")
                ]))
            } else if profile.usesStrongDM {
                fields.append(ConnectionIdentityField(label: "Auth Provider", value: "StrongDM"))
            } else if profile.usesTeleport {
                fields.append(ConnectionIdentityField(label: "Auth Provider", value: "Teleport"))
            }
            return fields
        }
    }

    private static func compactIdentityFields(_ values: [(String, String)]) -> [ConnectionIdentityField] {
        values.compactMap { label, rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : ConnectionIdentityField(label: label, value: value)
        }
    }

    private static func credentialDescription(_ kind: KubernetesCredentialKind) -> String {
        switch kind {
        case .none: "Not specified"
        case .bearerToken: "Bearer token"
        case .tokenFile: "Token file"
        case .execPlugin: "Exec plugin"
        case .clientCertificate: "Client certificate"
        case .basicAuth: "Basic authentication"
        case .authProvider: "Authentication provider"
        case .unknown: "Unknown"
        }
    }
}

enum ProviderIdentityParser {
    static func azureAccount(from output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = object["user"] as? [String: Any],
              let name = user["name"] as? String else {
            return nil
        }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
