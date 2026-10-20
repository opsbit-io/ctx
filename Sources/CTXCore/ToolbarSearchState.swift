import Foundation

/// Deterministic interaction state for the compact toolbar search control.
public struct ToolbarSearchState: Equatable, Sendable {
    public static let idleCollapseDelay: TimeInterval = 1.2

    public private(set) var query = ""
    public private(set) var isExpanded = false
    public private(set) var idleCollapseDeadline: Date?
    private var isFocused = false

    public init() {}

    public mutating func activate(at now: Date = Date()) {
        isExpanded = true
        updateIdleDeadline(at: now)
    }

    public mutating func setQuery(_ newQuery: String, at now: Date = Date()) {
        query = newQuery
        updateIdleDeadline(at: now)
    }

    public mutating func focusChanged(_ isFocused: Bool) {
        self.isFocused = isFocused
        if isFocused {
            idleCollapseDeadline = nil
        } else {
            collapse()
        }
    }

    public mutating func escape() {
        collapse()
    }

    public mutating func submit() -> String {
        let submittedQuery = query
        collapse()
        return submittedQuery
    }

    public mutating func resultSelected() {
        collapse()
    }

    public mutating func pointerExited() {
        // Pointer movement does not change an active search session.
    }

    @discardableResult
    public mutating func collapseIfIdle(at now: Date = Date()) -> Bool {
        guard isExpanded,
              !isFocused,
              query.isEmpty,
              let idleCollapseDeadline,
              now >= idleCollapseDeadline else {
            return false
        }
        collapse()
        return true
    }

    private mutating func updateIdleDeadline(at now: Date) {
        idleCollapseDeadline = isExpanded && !isFocused && query.isEmpty
            ? now.addingTimeInterval(Self.idleCollapseDelay)
            : nil
    }

    private mutating func collapse() {
        query = ""
        isExpanded = false
        isFocused = false
        idleCollapseDeadline = nil
    }
}
