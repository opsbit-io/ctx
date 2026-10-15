import Foundation

/// Matches user queries against non-secret metadata already discovered for a profile.
/// Search never reads credential files, invokes a provider CLI, or persists the query.
public enum ProfileSearchMatcher {
    public static func matches(_ profile: CloudProfile, query: String) -> Bool {
        matches(fields: searchableFields(for: profile), query: query)
    }

    /// Preserves a matching folder with all of its children. Otherwise, keeps only
    /// profiles whose discovered metadata matches and removes empty folders.
    public static func filteredGroups(_ groups: [ProfileGroup], query: String) -> [ProfileGroup] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }

        return groups.compactMap { group in
            let folderFields = [
                group.folder.name,
                group.folder.provider.rawValue,
                group.folder.provider.displayName,
                group.folder.provider.sectionHeaderTitle
            ]
            if matches(fields: folderFields, query: query) {
                return group
            }

            let profiles = group.profiles.filter { matches($0, query: query) }
            return profiles.isEmpty ? nil : ProfileGroup(folder: group.folder, profiles: profiles)
        }
    }

    private static func searchableFields(for profile: CloudProfile) -> [String] {
        [
            profile.name,
            profile.provider.rawValue,
            profile.provider.displayName,
            profile.provider.sectionHeaderTitle,
            profile.accountID,
            profile.roleName,
            profile.region,
            profile.ssoStartURL,
            profile.ssoRegion,
            profile.kubernetesLinkedProfile ?? ""
        ]
    }

    private static func matches(fields: [String], query: String) -> Bool {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { SearchTerm(String($0)) }

        guard !tokens.isEmpty else { return true }

        let terms = fields.map(SearchTerm.init)
        return tokens.allSatisfy { token in
            terms.contains { field in field.contains(token) }
        }
    }
}

private struct SearchTerm {
    let text: String
    let compact: String

    init(_ value: String) {
        text = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        compact = String(text.unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    func contains(_ other: SearchTerm) -> Bool {
        if text.contains(other.text) {
            return true
        }
        return !other.compact.isEmpty && compact.contains(other.compact)
    }
}
