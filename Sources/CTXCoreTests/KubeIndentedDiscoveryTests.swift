import CTXCore
import Foundation

func testIndentedKubeDiscoveryPreservesEntriesAndUsers() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: path) }
    // Both common serializers: unindented/indented lists, name before/after body.
    for padding in ["", "  ", "    "] {
        let sections = [
            "clusters:",
            "- cluster:\n    server: https://127.0.0.1:6443\n  name: broker-cluster\n- name: cloud-cluster\n  cluster:\n    server: https://example.com",
            "contexts:",
            "- context:\n    cluster: broker-cluster\n    user: sdm-broker\n  name: team-eks\n- name: cloud-context\n  context:\n    cluster: cloud-cluster\n    user: cloud-user",
            "users:",
            "- name: sdm-broker\n  user:\n    token: synthetic-test-value\n- user:\n    exec:\n      command: aws\n      env:\n      - name: AWS_PROFILE\n        value: team\n  name: cloud-user"
        ]
        let text = sections.enumerated().map { index, value in
            index.isMultiple(of: 2) ? value : value.split(separator: "\n").map { padding + $0 }.joined(separator: "\n")
        }.joined(separator: "\n")
        try text.write(to: path, atomically: true, encoding: .utf8)
        let result = KubeConfigDiscoveryService().discover(paths: [path])
        assert(result.contexts.count == 2)
        let broker = result.contexts.first { $0.contextName == "team-eks" }!
        assert(broker.userName == "sdm-broker")
        assert(broker.clusterMetadata.serverURL == "https://127.0.0.1:6443")
        assert(KubernetesProfileAdapter.cloudProfile(from: broker).usesStrongDM)
        let cloud = result.contexts.first { $0.contextName == "cloud-context" }!
        assert(cloud.credentialKind == .execPlugin && cloud.hasCredentials)
        assert(cloud.userName == "cloud-user")
        assert(cloud.linkedAWSProfile == "team")
    }
}

func testExplicitKubeAWSProfileDoesNotUseGlobalSelection() throws {
    func config(_ plugin: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["users": [["user": ["exec": plugin]]]])
    }
    let unlinked = try config(["command": "aws"])
    assert(ProfileCommandService.explicitAWSProfile(in: unlinked) == nil)
    let linked = try config(["command": "aws", "env": [["name": "AWS_PROFILE", "value": "team"]]])
    assert(ProfileCommandService.explicitAWSProfile(in: linked) == "team")
    let broker = try config(["command": "sdm", "env": [["name": "AWS_PROFILE", "value": "team"]]])
    assert(ProfileCommandService.explicitAWSProfile(in: broker) == nil)
    let explicit = try config(["command": "aws", "args": ["--profile", "other"], "env": [["name": "AWS_PROFILE", "value": "team"]]])
    assert(ProfileCommandService.explicitAWSProfile(in: explicit) == "other")
}

func testDiscoveryDoesNotTreatForeignExecEnvironmentAsAWSLink() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: path) }
    let text = """
    clusters:
    - name: broker-cluster
      cluster:
        server: https://127.0.0.1:6443
    contexts:
    - name: broker-context
      context:
        cluster: broker-cluster
        user: broker-user
    users:
    - name: broker-user
      user:
        exec:
          command: sdm
          env:
          - name: AWS_PROFILE
            value: unrelated-profile
    """
    try text.write(to: path, atomically: true, encoding: .utf8)

    let context = KubeConfigDiscoveryService().discover(paths: [path]).contexts.first
    assert(context?.credentialKind == .execPlugin)
    assert(context?.linkedAWSProfile == nil)
}

func testConnectionIdentityPresentationIsProviderScoped() {
    let aws = CloudProfile(
        provider: .aws,
        name: "team-admin",
        accountID: "123456789012",
        roleName: "AdministratorAccess"
    )
    let kube = CloudProfile(
        provider: .kubernetes,
        name: "team-cluster",
        accountID: "cluster-arn",
        roleName: "cluster-user",
        kubernetesCredentialKind: .execPlugin,
        hasKubernetesCredentials: true,
        kubernetesLinkedProfile: aws.name
    )
    let fields = ConnectionIdentityPresentation.fields(
        for: kube,
        linkedProfile: aws,
        resolvedIdentity: "operator@example.com"
    )
    let values = Dictionary(uniqueKeysWithValues: fields.map { ($0.label, $0.value) })
    assert(values["Kubernetes User"] == "cluster-user")
    assert(values["Auth Provider"] == "AWS EKS")
    assert(values["AWS Profile"] == "team-admin")
    assert(values["Account ID"] == "123456789012")
    assert(values["Role"] == "AdministratorAccess")
    assert(values["Caller Identity"] == "operator@example.com")
    assert(!fields.map(\.value).contains("unrelated-gcp@example.com"))

    let token = CloudProfile(
        provider: .kubernetes,
        name: "token-cluster",
        roleName: "token-user",
        kubernetesCredentialKind: .bearerToken,
        hasKubernetesCredentials: true
    )
    let tokenFields = ConnectionIdentityPresentation.fields(for: token)
    assert(tokenFields.contains(ConnectionIdentityField(label: "Credential Type", value: "Bearer token")))
    assert(!tokenFields.contains { $0.label == "Caller Identity" || $0.label == "AWS Profile" })

    let gcp = CloudProfile(provider: .gcp, name: "analytics", accountID: "demo-project", roleName: "configured@example.com")
    let gcpFields = ConnectionIdentityPresentation.fields(for: gcp, resolvedIdentity: "verified@example.com")
    assert(gcpFields.contains(ConnectionIdentityField(label: "Signed-in Account", value: "verified@example.com")))

    let azure = CloudProfile(provider: .azure, name: "production", accountID: "subscription-id", roleName: "tenant-id")
    let azureFields = ConnectionIdentityPresentation.fields(for: azure, resolvedIdentity: "verified@example.com")
    assert(azureFields.contains(ConnectionIdentityField(label: "Signed-in Account", value: "verified@example.com")))
}

func testLocalDiagnosticsAreBoundedAndExcludeIdentity() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = LocalDiagnostics(directory: directory, maximumBytes: 400)
    for _ in 0..<10 {
        try log.record(step: "test", contextID: "private-context-sentinel", outcome: "error")
    }
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    assert(files.count == 2)
    for file in files {
        let data = try Data(contentsOf: file)
        assert(data.count <= 400)
        assert(!String(decoding: data, as: UTF8.self).contains("private-context-sentinel"))
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
        assert(permissions.intValue == 0o600)
    }
}

@MainActor
func testDiscoveryRetainsContextsDuringFileReplacement() throws {
    let (store, directory, defaults, suite) = try makeLifecycleStore(profileNames: [], runner: LifecycleGateRunner())
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
    let path = directory.appendingPathComponent("missing-kubeconfig")
    let text = kubeconfig(context: "team", cluster: "team", user: "broker", server: "https://example.com")
    try text.write(to: path, atomically: true, encoding: .utf8)
    store.refreshImmediately(runVerification: false)
    assert(store.kubernetesContexts.count == 1)
    try FileManager.default.removeItem(at: path)
    store.refreshImmediately(runVerification: false)
    assert(store.kubernetesContexts.count == 1)
    assert(store.profiles.first { $0.provider == .kubernetes }?.status == .unknown)
    try "".write(to: path, atomically: true, encoding: .utf8)
    store.refreshImmediately(runVerification: false)
    assert(store.kubernetesContexts.count == 1)
    try text.replacingOccurrences(of: "team", with: "other").write(to: path, atomically: true, encoding: .utf8)
    store.refreshImmediately(runVerification: false)
    assert(store.kubernetesContexts.map(\.contextName) == ["other"])
}

@MainActor
func runKubeIndentedDiscoveryTests() throws {
    try testDiscoveryRetainsContextsDuringFileReplacement()
    testConnectionIdentityPresentationIsProviderScoped()
    try testDiscoveryDoesNotTreatForeignExecEnvironmentAsAWSLink()
    try testExplicitKubeAWSProfileDoesNotUseGlobalSelection()
    try testLocalDiagnosticsAreBoundedAndExcludeIdentity()
    try testIndentedKubeDiscoveryPreservesEntriesAndUsers()
}
