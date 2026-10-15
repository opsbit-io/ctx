import Foundation

extension ProfileStore {
    /// A nonzero cloud CLI exit is authoritative. StrongDM and Teleport are
    /// excluded because their verification poll resolves authentication.
    internal func reportLoginFailure(
        _ result: CommandResult,
        for profile: CloudProfile,
        operationID: UUID? = nil,
        origin: ProfilePresentationSurface = .mainWindow
    ) {
        if let operationID, !isCurrentOperation(profileID: profile.id, operationID: operationID) {
            return
        }
        dismissLifecyclePresentation(for: profile.id, from: origin)
        var message = result.output
        if profile.provider == .aws, let conflict = AWSCredentialsFileAudit.conflict(for: profile.name) {
            message += "\n\n" + conflict.explanation
        }
        report(message, title: "Connection Failed", from: origin)
    }

    internal func logConnectCall(step: String, kind: String, profileID: String, started: Date, outcome: String) {
        CTXPerfLog.log(
            step: step,
            contextID: profileID,
            namespace: "cluster",
            kind: kind,
            cache: .none,
            durationMs: max(0, Int(Date().timeIntervalSince(started) * 1000)),
            outcome: outcome == "success" ? .success : (outcome == "skipped" ? .skipped : .error)
        )
    }

    /// Extracts one-time authorization / verification codes emitted by cloud CLI device flows (e.g. AWS SSO, Azure, GitHub).
    public static func extractAuthCode(from text: String) -> String? {
        let patterns = [
            // AWS SSO / GitHub style: "and enter the code:\n\nABCD-EFGH" or "Then enter the code:\n\nABCD-EFGH" or "enter code: ABCD-EFGH"
            #"(?i)(?:enter|use|with)(?:\s+the)?\s+code:?\s*([A-Za-z0-9]{4}-[A-Za-z0-9]{4})"#,
            // Azure device code style: "enter the code CND38DFLK to authenticate"
            #"(?i)(?:enter|use)(?:\s+the)?\s+code\s+([A-Za-z0-9]{6,12})\b"#,
            // Generic "code: ABCD-EFGH"
            #"(?i)\bcode:\s*([A-Za-z0-9]{4}-[A-Za-z0-9]{4})\b"#,
            // Generic "code: CND38DFLK"
            #"(?i)\bcode:\s*([A-Za-z0-9]{6,12})\b"#,
            // URL query parameter user_code=ABCD-EFGH
            #"(?i)[?&]user_code=([A-Za-z0-9-]+)"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                let candidate = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    return candidate.uppercased()
                }
            }
        }
        return nil
    }

    /// Appends the `user_code` query parameter to RFC 8628 verification endpoints when supported.
    public static func urlWithUserCode(_ url: URL, code: String) -> URL {
        guard let host = url.host?.lowercased(),
              host.contains("device.sso") || host.contains("devicelogin") || host.contains("github.com") else {
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url
        }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name.lowercased() == "user_code" }) {
            items.append(URLQueryItem(name: "user_code", value: code))
            components.queryItems = items
            return components.url ?? url
        }
        return url
    }

    internal func openAuthURLIfPresent(
        _ text: String,
        email: String? = nil,
        operationID: UUID? = nil,
        profileID: String? = nil,
        origin: ProfilePresentationSurface = .mainWindow
    ) {
        if let operationID, let profileID,
           !isCurrentOperation(profileID: profileID, operationID: operationID) {
            return
        }

        let fullText: String
        if let operationID {
            let accumulated = (authOutputBuffers[operationID] ?? "") + "\n" + text
            authOutputBuffers[operationID] = accumulated
            fullText = accumulated
        } else {
            fullText = text
        }

        let extractedCode = Self.extractAuthCode(from: fullText)

        // If in-app auth is already displayed for this operation, check if we should populate the user code:
        if let operationID,
           let current = presentation,
           case .inAppAuth(let existing) = current.route,
           existing.operationID == operationID {
            if existing.userCode == nil, let code = extractedCode {
                let targetURL = Self.urlWithUserCode(existing.url, code: code)
                presentation = ProfilePresentation(
                    id: current.id,
                    origin: current.origin,
                    requestedOrigin: current.requestedOrigin,
                    route: .inAppAuth(
                        InAppAuthPresentation(
                            url: targetURL,
                            userCode: code,
                            email: existing.email,
                            profileID: existing.profileID,
                            operationID: existing.operationID
                        )
                    )
                )
            }
            return
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(
            in: fullText,
            options: [],
            range: NSRange(location: 0, length: fullText.utf16.count)
        )
        for match in matches ?? [] {
            guard let url = match.url, url.scheme?.hasPrefix("http") == true else { continue }
            if let host = url.host?.lowercased(), host == "127.0.0.1" || host == "localhost" {
                continue
            }
            guard let operationID, let profileID else { return }

            let targetURL = extractedCode != nil ? Self.urlWithUserCode(url, code: extractedCode!) : url

            present(
                .inAppAuth(
                    InAppAuthPresentation(
                        url: targetURL,
                        userCode: extractedCode,
                        email: email,
                        profileID: profileID,
                        operationID: operationID
                    )
                ),
                from: origin
            )
            break
        }
    }

    internal func dismissInAppAuth(
        profileID: String,
        operationID: UUID,
        origin: ProfilePresentationSurface
    ) {
        authOutputBuffers.removeValue(forKey: operationID)
        guard let current = presentation,
              current.requestedOrigin == origin,
              case .inAppAuth(let request) = current.route,
              request.profileID == profileID,
              request.operationID == operationID else {
            return
        }
        presentation = nil
    }

    internal func dismissLifecyclePresentation(
        for profileID: String,
        from origin: ProfilePresentationSurface
    ) {
        guard let current = presentation, current.requestedOrigin == origin else { return }
        switch current.route {
        case .missingCLI(let request) where request.profile.id == profileID:
            presentation = nil
        case .inAppAuth(let request) where request.profileID == profileID:
            authOutputBuffers.removeValue(forKey: request.operationID)
            presentation = nil
        default:
            break
        }
    }

    public func cancelPresentation(id: UUID, from surface: ProfilePresentationSurface) {
        guard let current = presentation,
              current.id == id,
              current.origin == surface else {
            return
        }
        if case .inAppAuth(let request) = current.route,
           isCurrentOperation(profileID: request.profileID, operationID: request.operationID) {
            authOutputBuffers.removeValue(forKey: request.operationID)
            if let profile = profiles.first(where: { $0.id == request.profileID }) {
                updateStatus(profile, status: .needsLogin, operationID: request.operationID)
            }
            cancelProfileOperation(profileID: request.profileID)
        }
        consumePresentation(id: id, from: surface)
    }
}
