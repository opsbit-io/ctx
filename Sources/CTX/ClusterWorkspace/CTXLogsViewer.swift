import SwiftUI

/// Shared inspection log panel: monospaced, scrollable, optional line-wrap,
/// optional ANSI-escape stripping for readability, semantic log-level coloring
/// (display only — Copy always uses the untouched raw text), level filtering,
/// line count, and auto-scroll to the newest line whenever the text changes.
struct CTXLogsViewer: View {
    let rawText: String
    let tailLines: Int

    enum LogLevelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case errors = "Errors"
        case warnings = "Warnings"
        var id: String { rawValue }
    }

    @State private var wrapLines = true
    @State private var stripANSI = true
    @State private var levelFilter: LogLevelFilter = .all
    @State private var filterQuery = ""
    @State private var fontSize: CGFloat = 11.5

    private static let bottomAnchorID = "ctx-logs-bottom"

    @State private var cachedFilteredText: String = ""
    @State private var cachedStyledLog = AttributedString("")
    @State private var errorLineCount: Int = 0
    @State private var warnLineCount: Int = 0
    @State private var totalLineCount: Int = 0

    private func updateCachedFilteredText() {
        let base = stripANSI ? Self.strippingANSICodes(from: rawText) : rawText
        let allLines = base.isEmpty ? [] : base.components(separatedBy: .newlines)
        totalLineCount = allLines.count

        var errs = 0
        var warns = 0
        for line in allLines {
            let lower = line.lowercased()
            if Self.isErrorLine(lower) {
                errs += 1
            } else if Self.isWarnLine(lower) {
                warns += 1
            }
        }
        errorLineCount = errs
        warnLineCount = warns

        let trimmedQuery = filterQuery.trimmingCharacters(in: .whitespaces)
        let query = trimmedQuery.lowercased()

        let filtered = allLines.filter { line in
            let lower = line.lowercased()
            switch levelFilter {
            case .all:
                break
            case .errors:
                guard Self.isErrorLine(lower) else { return false }
            case .warnings:
                guard Self.isWarnLine(lower) || Self.isErrorLine(lower) else { return false }
            }
            if !query.isEmpty {
                return lower.contains(query)
            }
            return true
        }

        cachedFilteredText = filtered.joined(separator: "\n")
        cachedStyledLog = Self.dimmingLeadingTimestamps(in: cachedFilteredText)
    }

    private static func isErrorLine(_ lower: String) -> Bool {
        lower.contains("error") || lower.contains("fatal") || lower.contains("panic") || lower.contains("exception") || lower.contains(" level=err") || lower.contains("\"level\":\"error\"")
    }

    private static func isWarnLine(_ lower: String) -> Bool {
        lower.contains("warn") || lower.contains("backoff") || lower.contains("timeout") || lower.contains("\"level\":\"warn\"")
    }

    private var lineCount: Int {
        cachedFilteredText.isEmpty ? 0 : cachedFilteredText.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // Search inside log output
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Search in log stream...", text: $filterQuery)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !filterQuery.isEmpty {
                        Button {
                            filterQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(minWidth: 160, maxWidth: 260)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                // Quick Log Level Pills
                HStack(spacing: 5) {
                    levelPill(.all, label: "All (\(totalLineCount))", tint: .accentColor)
                    if errorLineCount > 0 {
                        levelPill(.errors, label: "Errors (\(errorLineCount))", tint: .red)
                    }
                    if warnLineCount > 0 {
                        levelPill(.warnings, label: "Warnings (\(warnLineCount))", tint: .orange)
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 10) {
                    Text("\(lineCount) lines")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Divider().frame(height: 12)

                    Toggle("Wrap", isOn: $wrapLines)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Toggle("Clean ANSI", isOn: $stripANSI)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Divider().frame(height: 12)

                    Button {
                        fontSize = max(9, fontSize - 1)
                    } label: {
                        Text("A-").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)

                    Text("\(Int(fontSize))pt")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(.secondary)

                    Button {
                        fontSize = min(16, fontSize + 1)
                    } label: {
                        Text("A+").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))

            Divider().opacity(0.55)

            ScrollViewReader { proxy in
                ScrollView(wrapLines ? [.vertical] : [.vertical, .horizontal]) {
                    if cachedFilteredText.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("No log lines match the current filter")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        Text(styledLog)
                            .font(.system(size: fontSize, design: .monospaced))
                            .lineSpacing(2.5)
                            .textSelection(.enabled)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .id(Self.bottomAnchorID)
                    }
                }
                .background(Color.black.opacity(0.18))
                .onChange(of: rawText) { _, _ in
                    updateCachedFilteredText()
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
                .onChange(of: stripANSI) { _, _ in
                    updateCachedFilteredText()
                }
                .onChange(of: levelFilter) { _, _ in
                    updateCachedFilteredText()
                }
                .onChange(of: filterQuery) { _, _ in
                    updateCachedFilteredText()
                }
                .onAppear {
                    updateCachedFilteredText()
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            .frame(minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func levelPill(_ filter: LogLevelFilter, label: String, tint: Color) -> some View {
        let isSelected = levelFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                levelFilter = (levelFilter == filter && filter != .all) ? .all : filter
            }
        } label: {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(isSelected ? tint.opacity(0.20) : Color.secondary.opacity(0.08), in: Capsule())
                .overlay {
                    Capsule().stroke(isSelected ? tint.opacity(0.55) : Color.clear, lineWidth: 1)
                }
                .foregroundStyle(isSelected ? tint : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var styledLog: AttributedString {
        cachedStyledLog
    }

    static func strippingANSICodes(from text: String) -> String {
        guard text.contains("\u{1B}[") else { return text }
        guard let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[A-Za-z]") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    static func dimmingLeadingTimestamps(in text: String) -> AttributedString {
        guard !text.isEmpty else { return AttributedString("") }
        var result = AttributedString(text)
        let nsString = text as NSString
        let fullLength = nsString.length
        guard fullLength > 0, fullLength < 350_000 else { return result }

        // Highlight ERROR / FATAL / WARN / INFO tokens for instant visual scanning
        if let errRegex = try? NSRegularExpression(pattern: "\\b(ERROR|FATAL|PANIC|Exception|ERR)\\b", options: [.caseInsensitive]) {
            for match in errRegex.matches(in: text, range: NSRange(location: 0, length: fullLength)) {
                if let r = Range(match.range, in: result) {
                    result[r].foregroundColor = .red
                }
            }
        }
        if let warnRegex = try? NSRegularExpression(pattern: "\\b(WARN|WARNING|BackOff)\\b", options: [.caseInsensitive]) {
            for match in warnRegex.matches(in: text, range: NSRange(location: 0, length: fullLength)) {
                if let r = Range(match.range, in: result) {
                    result[r].foregroundColor = .orange
                }
            }
        }
        return result
    }
}
