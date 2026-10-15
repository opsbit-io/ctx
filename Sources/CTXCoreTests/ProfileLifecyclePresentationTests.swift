import CTXCore
import Foundation

final class MissingCLISequence: @unchecked Sendable {
    private let lock = NSLock()
    private var returnsMissing = true

    func resolve(_ profile: CloudProfile) -> CLITool? {
        lock.lock()
        defer { lock.unlock() }
        if returnsMissing {
            returnsMissing = false
            return .aws
        }
        return nil
    }
}

@MainActor
func testMissingCLIRetryPublicationIsGenerationGated() async throws {
    let runner = LifecycleGateRunner()
    let resolver = MissingCLISequence()
    let (store, directory, defaults, suiteName) = try makeLifecycleStore(
        profileNames: ["alpha"],
        runner: runner,
        missingCLIToolResolver: { resolver.resolve($0) }
    )
    defer {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
    let profile = store.profiles.first!

    store.login(profile, from: .menuBar)
    guard let missingPresentation = store.presentation,
          missingPresentation.origin == .mainWindow,
          missingPresentation.requestedOrigin == .menuBar,
          case .missingCLI(let request) = missingPresentation.route else {
        assertionFailure("menu-bar routes must fall back to the main-window host")
        return
    }
    assert(request.profile.id == profile.id)
    store.retryMissingCLI(request, from: .mainWindow)
    await runner.waitForCommandCount(1)
    store.logout(profile, from: .menuBar)
    await runner.releaseCommand(0, result: CommandResult(exitCode: 0, output: "late retry success"))
    await waitForLifecycleCondition("menu-bar disconnect completion") {
        store.profiles.first?.status != .disconnecting
    }

    assert(store.presentation == nil)
    assert(store.profiles.first?.status == .needsLogin)
}

@MainActor
func testPresentationRoutesAreOriginFilteredAndReportIsTyped() throws {
    let runner = LifecycleGateRunner()
    let (store, directory, defaults, suiteName) = try makeLifecycleStore(
        profileNames: ["alpha"],
        runner: runner
    )
    defer {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    let previousStatus = store.lastMessage
    store.report("token=private-value", from: .settings)
    guard let route = store.presentation(for: .settings),
          case .operationError(let error) = route.route else {
        assertionFailure("report must publish a typed operation error")
        return
    }
    assert(store.presentation(for: .mainWindow) == nil)
    assert(!error.message.contains("private-value"), "operation errors must redact secret assignments")
    assert(store.lastMessage == previousStatus, "critical errors must not be published as status text")

    store.consumePresentation(id: route.id, from: .mainWindow)
    assert(store.presentation?.id == route.id, "only the originating surface may consume a route")
    store.consumePresentation(id: route.id, from: .settings)
    assert(store.presentation == nil)

    store.reportStatus("Profile saved")
    assert(store.lastMessage == "Profile saved")
    assert(store.presentation == nil, "successful status must not create an error route")
}

@MainActor
func testPresentationConsumptionUsesExactRouteID() async throws {
    let store = ProfileStore(startsBackgroundServices: false)
    store.presentProfileEditor(.selectProvider(targetFolder: nil), from: .mainWindow)
    let dismissedID = store.presentation!.id

    store.report("newer failure", from: .mainWindow)
    assert(store.presentation?.id == dismissedID, "an alert must not replace a live sheet")
    store.consumePresentation(id: dismissedID, from: .mainWindow)
    await waitForLifecycleCondition("queued operation error presentation") {
        store.presentation != nil
    }

    guard case .operationError = store.presentation?.route else {
        assertionFailure("the queued operation error must follow sheet dismissal")
        return
    }
    let replacementID = store.presentation!.id
    store.consumePresentation(id: dismissedID, from: .mainWindow)
    assert(store.presentation?.id == replacementID, "a stale sheet dismissal must not consume its replacement")
}

@MainActor
func testAuthDismissPreservesNewerOperationError() async throws {
    let store = ProfileStore(startsBackgroundServices: false)
    let request = InAppAuthPresentation(
        url: URL(string: "https://example.com/device")!,
        email: nil,
        profileID: "aws:alpha",
        operationID: UUID()
    )
    store.present(.inAppAuth(request), from: .mainWindow)
    let authID = store.presentation!.id

    store.report("authentication failed", from: .mainWindow)
    assert(store.presentation?.id == authID, "a background error must remain queued while auth is visible")
    store.consumePresentation(id: authID, from: .mainWindow)
    await waitForLifecycleCondition("queued authentication error presentation") {
        store.presentation != nil
    }

    guard case .operationError = store.presentation?.route else {
        assertionFailure("the queued background error must appear after auth dismissal")
        return
    }
}

@MainActor
func testAuthCancellationStopsTheOwningConnectOperation() async throws {
    let runner = LifecycleGateRunner()
    let (store, directory, defaults, suiteName) = try makeLifecycleStore(
        profileNames: ["alpha"],
        runner: runner
    )
    defer {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
    let profile = store.profiles.first!

    store.login(profile)
    await runner.waitForCommandCount(1)
    await runner.emitOutput("Continue at https://example.com/device", forCommand: 0)
    await waitForLifecycleCondition("in-app authentication presentation") {
        if case .inAppAuth = store.presentation?.route {
            return true
        }
        return false
    }
    let presentationID = store.presentation!.id

    store.cancelPresentation(id: presentationID, from: .mainWindow)
    assert(store.presentation == nil)
    assert(store.profiles.first?.status == .needsLogin)

    await runner.releaseCommand(0, result: CommandResult(exitCode: 0, output: "late login success"))
    await Task.yield()
    assert(store.profiles.first?.status == .needsLogin, "cancelled authentication completed in the background")
}

@MainActor
func testProviderSelectionSwapsEditorInsideTheOpenSheet() async throws {
    let store = ProfileStore(startsBackgroundServices: false)
    store.presentProfileEditor(.selectProvider(targetFolder: nil), from: .mainWindow)
    let selectionID = store.presentation!.id

    store.presentProfileEditor(.add(provider: .aws, targetFolder: nil), from: .mainWindow)

    guard let editor = store.presentation,
          case .profileEditor(.add(let provider, _)) = editor.route else {
        assertionFailure("provider selection must transition to the requested editor")
        return
    }
    assert(provider == .aws)
    // Keeping the identity keeps the sheet on screen: a new one would dismiss
    // and re-present, which users see as the window stalling mid-step.
    assert(editor.id == selectionID, "stepping into an editor must reuse the open sheet")

    // The swap must be immediate rather than queued behind a dismissal.
    await Task.yield()
    await Task.yield()
    assert(store.presentation?.id == selectionID, "the editor must survive without a deferred re-present")
}

@MainActor
func testAWSExportRequiresExactActiveConnectedProfile() async throws {
    let runner = LifecycleGateRunner()
    let (store, directory, defaults, suiteName) = try makeLifecycleStore(
        profileNames: ["alpha", "beta"],
        runner: runner,
        activeAWSProfile: "alpha"
    )
    defer {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
    let alpha = store.profiles.first { $0.name == "alpha" }!
    let beta = store.profiles.first { $0.name == "beta" }!

    assert(!store.canExportAWSCredentials(alpha), "selected but disconnected AWS profile must not export")

    let verifyAlpha = Task { await store.verify(alpha, isManualAttempt: true) }
    await runner.waitForCommandCount(1)
    await runner.releaseCommand(0, result: CommandResult(exitCode: 0, output: #"{"Account":"123456789012"}"#))
    _ = await verifyAlpha.value
    assert(store.canExportAWSCredentials(alpha), "the exact active connected profile should export")

    let verifyBeta = Task { await store.verify(beta, isManualAttempt: true) }
    await runner.waitForCommandCount(2)
    await runner.releaseCommand(1, result: CommandResult(exitCode: 0, output: #"{"Account":"123456789012"}"#))
    _ = await verifyBeta.value
    assert(!store.canExportAWSCredentials(beta), "another connected profile must not export")
}

@MainActor
func testMenuPresentationFallsBackToMainWindow() throws {
    let store = ProfileStore(startsBackgroundServices: false)
    store.report("menu failure", from: .menuBar)

    assert(store.presentation(for: .menuBar) == nil)
    assert(store.presentation(for: .mainWindow)?.requestedOrigin == .menuBar)
    guard case .operationError = store.presentation(for: .mainWindow)?.route else {
        assertionFailure("menu failures must be hosted by the main window")
        return
    }
}

@MainActor
func testMenuProviderSignOutConfirmsOnHostAndRetainsOrigin() async throws {
    let runner = LifecycleGateRunner()
    let (store, directory, defaults, suiteName) = try makeLifecycleStore(
        profileNames: ["alpha"],
        runner: runner
    )
    defer {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
    let profile = store.profiles.first!
    store.requestProviderSignOut(profile, from: .menuBar)
    guard let presentation = store.presentation,
          presentation.origin == .mainWindow,
          presentation.requestedOrigin == .menuBar,
          case .providerSignOutConfirmation(let confirmation) = presentation.route else {
        assertionFailure("menu sign-out confirmation must be hosted by the main window")
        return
    }

    store.confirmProviderSignOut(confirmation, from: .mainWindow)
    await runner.waitForCommandCount(1)
    await runner.releaseCommand(0, result: CommandResult(exitCode: 1, output: "sign-out failed"))
    await waitForLifecycleCondition("provider sign-out failure presentation") {
        store.presentation != nil
    }

    assert(store.presentation?.origin == .mainWindow)
    assert(store.presentation?.requestedOrigin == .menuBar)
}

@MainActor
func testLifecycleSanitizerRedactsAWSAndAuthorizationSecrets() throws {
    let store = ProfileStore(startsBackgroundServices: false)
    let secrets = [
        #"{"AccessKeyId":"AKIAEXAMPLE","SecretAccessKey":"aws-secret","SessionToken":"session-secret"}"#,
        "Authorization: Bearer header.payload.signature",
        "authorization=header.payload.signature",
        "AWS_SECRET_ACCESS_KEY=another-secret"
    ]
    store.report(secrets.joined(separator: "\n"), from: .mainWindow)

    guard case .operationError(let error) = store.presentation?.route else {
        assertionFailure("sanitizer test requires an operation error")
        return
    }
    for secret in ["AKIAEXAMPLE", "aws-secret", "session-secret", "header.payload.signature", "another-secret"] {
        assert(!error.message.contains(secret), "sanitizer leaked \(secret)")
    }
}

@MainActor
func testFolderEditorDeleteSequenceDoesNotClobberNewerRoute() async throws {
    let store = ProfileStore(startsBackgroundServices: false)
    let folder = CloudFolder.builtIn(provider: .aws, environment: .production)
    store.presentFolderEditor(.edit(folder), from: .mainWindow)
    let editorID = store.presentation!.id

    store.requestFolderDeletionAfterDismissingEditor(
        folder,
        editorPresentationID: editorID,
        from: .mainWindow
    )
    store.report("newer failure", from: .mainWindow)
    await Task.yield()
    await Task.yield()

    guard case .operationError = store.presentation?.route else {
        assertionFailure("deferred folder confirmation must not replace a newer route")
        return
    }

    store.consumePresentation(id: store.presentation!.id, from: .mainWindow)
    store.presentFolderEditor(.edit(folder), from: .mainWindow)
    store.requestFolderDeletionAfterDismissingEditor(
        folder,
        editorPresentationID: store.presentation!.id,
        from: .mainWindow
    )
    await Task.yield()
    await Task.yield()
    guard case .folderDeletionConfirmation(let requestedFolder) = store.presentation?.route else {
        assertionFailure("folder confirmation must follow editor dismissal")
        return
    }
    assert(requestedFolder.id == folder.id)
}

@MainActor
func testAsyncLifecycleFailureRetainsOrigin() async throws {
    let runner = LifecycleGateRunner()
    let (store, directory, defaults, suiteName) = try makeLifecycleStore(
        profileNames: ["alpha"],
        runner: runner
    )
    defer {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
    let profile = store.profiles.first!

    store.login(profile, from: .settings)
    await runner.waitForCommandCount(1)
    await runner.releaseCommand(
        0,
        result: CommandResult(exitCode: 1, output: "authentication failed")
    )
    await waitForLifecycleCondition("asynchronous lifecycle failure presentation") {
        store.presentation != nil
    }

    assert(store.presentation?.origin == .settings)
    guard case .operationError = store.presentation?.route else {
        assertionFailure("async failure must publish an operation error route")
        return
    }
    assert(store.presentation(for: .mainWindow) == nil)
}

@MainActor
func testDeviceAuthCodeExtraction() throws {
    // 1. AWS SSO standard CLI output with newlines
    let awsOutput = """
    Using a browser, open the following URL:

    https://device.sso.eu-central-1.amazonaws.com/

    and enter the code:

    ABCD-EFGH
    """
    assert(ProfileStore.extractAuthCode(from: awsOutput) == "ABCD-EFGH")

    // 2. AWS SSO with "Then enter the code:"
    let awsAltOutput = """
    If the browser does not open or you wish to use a different device to authorize this request, open the following URL:

    https://device.sso.us-east-1.amazonaws.com/

    Then enter the code:

    1234-5678
    """
    assert(ProfileStore.extractAuthCode(from: awsAltOutput) == "1234-5678")

    // 3. Azure device login
    let azureOutput = "To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code CND38DFLK to authenticate."
    assert(ProfileStore.extractAuthCode(from: azureOutput) == "CND38DFLK")

    // 4. URL query parameter
    let urlWithCode = "https://device.sso.eu-central-1.amazonaws.com/?user_code=QWER-TYUI"
    assert(ProfileStore.extractAuthCode(from: urlWithCode) == "QWER-TYUI")

    // 5. Generic prompt
    let genericOutput = "Please verify your session with code: ABCD-WXYZ"
    assert(ProfileStore.extractAuthCode(from: genericOutput) == "ABCD-WXYZ")
}

@MainActor
func testDeviceAuthURLAugmentation() throws {
    let rawAWSURL = URL(string: "https://device.sso.eu-central-1.amazonaws.com/")!
    let augmentedAWS = ProfileStore.urlWithUserCode(rawAWSURL, code: "ABCD-EFGH")
    assert(augmentedAWS.absoluteString == "https://device.sso.eu-central-1.amazonaws.com/?user_code=ABCD-EFGH")

    // If user_code is already present, it should not be duplicated
    let alreadyPresent = URL(string: "https://device.sso.eu-central-1.amazonaws.com/?user_code=ABCD-EFGH")!
    let notDuplicated = ProfileStore.urlWithUserCode(alreadyPresent, code: "ABCD-EFGH")
    assert(notDuplicated.absoluteString == "https://device.sso.eu-central-1.amazonaws.com/?user_code=ABCD-EFGH")

    // Non-device URLs should not be modified
    let googleURL = URL(string: "https://accounts.google.com/o/oauth2/auth")!
    let unmodified = ProfileStore.urlWithUserCode(googleURL, code: "ABCD-EFGH")
    assert(unmodified.absoluteString == "https://accounts.google.com/o/oauth2/auth")
}

@MainActor
func testDeviceAuthStreamingChunksUpdatesPresentation() async throws {
    let runner = LifecycleGateRunner()
    let (store, directory, defaults, suiteName) = try makeLifecycleStore(
        profileNames: ["alpha"],
        runner: runner
    )
    defer {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
    let profile = store.profiles.first!

    store.login(profile)
    await runner.waitForCommandCount(1)

    // Emit chunk 1: URL only
    await runner.emitOutput("Using a browser, open the following URL:\nhttps://device.sso.eu-central-1.amazonaws.com/\n", forCommand: 0)

    await waitForLifecycleCondition("initial in-app authentication presentation") {
        if case .inAppAuth(let req) = store.presentation?.route {
            return req.url.host?.contains("device.sso") == true
        }
        return false
    }

    guard case .inAppAuth(let initialReq) = store.presentation?.route else {
        assertionFailure("inAppAuth route expected")
        return
    }
    assert(initialReq.userCode == nil, "Initial chunk had no code yet")

    // Emit chunk 2: Code arrives in subsequent chunk
    await runner.emitOutput("and enter the code:\n\nABCD-EFGH\n", forCommand: 0)

    await waitForLifecycleCondition("updated in-app authentication presentation with code") {
        if case .inAppAuth(let req) = store.presentation?.route {
            return req.userCode == "ABCD-EFGH"
        }
        return false
    }

    guard case .inAppAuth(let updatedReq) = store.presentation?.route else {
        assertionFailure("updated inAppAuth route expected")
        return
    }
    assert(updatedReq.userCode == "ABCD-EFGH")
    assert(updatedReq.url.query?.contains("user_code=ABCD-EFGH") == true, "URL must be augmented with user_code")

    // Cleanup: cancel presentation
    let presentationID = store.presentation!.id
    store.cancelPresentation(id: presentationID, from: .mainWindow)
    assert(store.presentation == nil)

    await runner.releaseCommand(0, result: CommandResult(exitCode: 15, output: "cancelled"))
    await Task.yield()
}

@MainActor
func runProfileLifecyclePresentationTests() async throws {
    try testDeviceAuthCodeExtraction()
    try testDeviceAuthURLAugmentation()
    try await testDeviceAuthStreamingChunksUpdatesPresentation()
    try await testMissingCLIRetryPublicationIsGenerationGated()
    try testPresentationRoutesAreOriginFilteredAndReportIsTyped()
    try await testPresentationConsumptionUsesExactRouteID()
    try await testAuthDismissPreservesNewerOperationError()
    try await testAuthCancellationStopsTheOwningConnectOperation()
    try await testProviderSelectionSwapsEditorInsideTheOpenSheet()
    try await testAWSExportRequiresExactActiveConnectedProfile()
    try testMenuPresentationFallsBackToMainWindow()
    try await testMenuProviderSignOutConfirmsOnHostAndRetainsOrigin()
    try testLifecycleSanitizerRedactsAWSAndAuthorizationSecrets()
    try await testFolderEditorDeleteSequenceDoesNotClobberNewerRoute()
    try await testAsyncLifecycleFailureRetainsOrigin()
}
