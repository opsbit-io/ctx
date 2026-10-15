import CTXCore
import SwiftUI

/// Provider → folder → profile grouping, shared by the sidebar and the menu bar.
///
/// Both screens present the same tree and previously carried their own verbatim
/// copies of all of this: the search filter, the `ProviderGroup` type, the provider
/// rollup, and both disclosure bindings. Any change to how profiles are grouped or
/// searched had to be made twice, identically, to keep the two views agreeing.
struct ProviderGroup: Identifiable {
    var id: CloudProvider { provider }
    let provider: CloudProvider
    let folderGroups: [ProfileGroup]

    var profileCount: Int {
        folderGroups.reduce(0) { $0 + $1.profiles.count }
    }

    var hasConnectedProfile: Bool {
        folderGroups.contains { group in
            group.profiles.contains { $0.status == .connected }
        }
    }
}

enum ProfileGrouping {
    /// Folder groups matching `query`. A folder whose own name matches keeps all of
    /// its profiles; otherwise only the matching profiles are kept, and a folder
    /// with no matches drops out.
    static func filtered(_ groups: [ProfileGroup], query: String) -> [ProfileGroup] {
        ProfileSearchMatcher.filteredGroups(groups, query: query)
    }

    /// The filtered groups rolled up by provider, skipping providers with nothing
    /// to show.
    static func providerGroups(_ groups: [ProfileGroup], query: String) -> [ProviderGroup] {
        let filtered = filtered(groups, query: query)
        return CloudProvider.allCases.compactMap { provider in
            let forProvider = filtered.filter { $0.folder.provider == provider && !$0.profiles.isEmpty }
            return forProvider.isEmpty ? nil : ProviderGroup(provider: provider, folderGroups: forProvider)
        }
    }

    /// A disclosure binding over a set of expanded ids. An active search forces
    /// everything open so matches deeper in the tree are actually visible.
    static func expansionBinding<ID: Hashable>(
        for id: ID,
        in expanded: Binding<Set<ID>>,
        forcedOpenWhile query: String
    ) -> Binding<Bool> {
        Binding(
            get: { expanded.wrappedValue.contains(id) || !query.isEmpty },
            set: { isExpanded in
                if isExpanded {
                    expanded.wrappedValue.insert(id)
                } else {
                    expanded.wrappedValue.remove(id)
                }
            }
        )
    }
}
