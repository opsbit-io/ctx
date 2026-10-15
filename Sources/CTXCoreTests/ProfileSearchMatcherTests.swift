import CTXCore

private func assertMatches(_ profile: CloudProfile, _ query: String) {
    assert(ProfileSearchMatcher.matches(profile, query: query), "Expected profile to match: \(query)")
}

private func assertDoesNotMatch(_ profile: CloudProfile, _ query: String) {
    assert(!ProfileSearchMatcher.matches(profile, query: query), "Expected profile not to match: \(query)")
}

func runProfileSearchMatcherTests() {
    let aws = CloudProfile(
        provider: .aws,
        name: "store-production",
        accountID: "111122223333",
        roleName: "PlatformAdministrator",
        region: "eu-west-1",
        ssoStartURL: "https://example.awsapps.com/start",
        ssoRegion: "us-east-1"
    )
    assertMatches(aws, "111122223333")
    assertMatches(aws, "1111-2222-3333")
    assertMatches(aws, "AWS 2222 production")
    assertMatches(aws, "platformadministrator EU-WEST")
    assertMatches(aws, "example.awsapps.com")
    assertDoesNotMatch(aws, "111122223334")
    assertDoesNotMatch(aws, "production readonly")

    let gcp = CloudProfile(
        provider: .gcp,
        name: "analytics",
        accountID: "sample-data-platform",
        roleName: "developer@example.com",
        region: "europe-west1"
    )
    assertMatches(gcp, "sample data platform")
    assertMatches(gcp, "developer@example.com")
    assertMatches(gcp, "google europe-west1")

    let azure = CloudProfile(
        provider: .azure,
        name: "shared-services",
        accountID: "12345678-abcd-4321-abcd-123456789abc",
        roleName: "tenant-example",
        region: "westeurope"
    )
    assertMatches(azure, "12345678abcd")
    assertMatches(azure, "azure tenant-example")

    let kubernetes = CloudProfile(
        provider: .kubernetes,
        name: "orders-prod",
        accountID: "orders-cluster",
        roleName: "cluster-user",
        region: "orders-namespace",
        kubernetesLinkedProfile: "store-production"
    )
    assertMatches(kubernetes, "orders cluster-user")
    assertMatches(kubernetes, "orders-namespace")
    assertMatches(kubernetes, "store production")

    assertMatches(aws, "   ")

    let production = CloudFolder.builtIn(provider: .aws, environment: .production)
    let development = CloudFolder.builtIn(provider: .gcp, environment: .development)
    let groups = [
        ProfileGroup(folder: production, profiles: [aws]),
        ProfileGroup(folder: development, profiles: [gcp])
    ]

    let folderMatch = ProfileSearchMatcher.filteredGroups(groups, query: "production")
    assert(folderMatch.count == 1)
    assert(folderMatch.first?.profiles == [aws], "A folder match must retain all children")

    let metadataMatch = ProfileSearchMatcher.filteredGroups(groups, query: "developer@example.com")
    assert(metadataMatch.count == 1)
    assert(metadataMatch.first?.profiles == [gcp])

    assert(ProfileSearchMatcher.filteredGroups(groups, query: "missing-account").isEmpty)
    let emptyQuery = ProfileSearchMatcher.filteredGroups(groups, query: "  ")
    assert(emptyQuery.map(\.folder.id) == groups.map(\.folder.id))
    assert(emptyQuery.flatMap(\.profiles) == groups.flatMap(\.profiles))
}
