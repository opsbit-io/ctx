import AppKit
import CTXCore
import SwiftUI

// MARK: - Smart Kubernetes Table Value Parser & Comparator

public enum CTXTableValueParser {
    /// Parses an Age string like "2mo", "36d", "5h", "12m", "30s", "1y", "5d2h" into total seconds.
    public static func parseAgeToSeconds(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed != "-" else { return nil }

        var totalSeconds: Double = 0
        var currentDigits = ""
        var foundUnit = false

        var i = trimmed.startIndex
        while i < trimmed.endIndex {
            let ch = trimmed[i]
            if ch.isNumber || ch == "." {
                currentDigits.append(ch)
                i = trimmed.index(after: i)
            } else {
                guard let val = Double(currentDigits) else { break }
                currentDigits = ""
                foundUnit = true
                let remaining = trimmed[i...]
                if remaining.hasPrefix("mo") {
                    totalSeconds += val * 30 * 86400
                    i = trimmed.index(i, offsetBy: 2)
                } else if remaining.hasPrefix("m") {
                    totalSeconds += val * 60
                    i = trimmed.index(after: i)
                } else if remaining.hasPrefix("h") {
                    totalSeconds += val * 3600
                    i = trimmed.index(after: i)
                } else if remaining.hasPrefix("d") {
                    totalSeconds += val * 86400
                    i = trimmed.index(after: i)
                } else if remaining.hasPrefix("s") {
                    totalSeconds += val
                    i = trimmed.index(after: i)
                } else if remaining.hasPrefix("y") {
                    totalSeconds += val * 365 * 86400
                    i = trimmed.index(after: i)
                } else {
                    i = trimmed.index(after: i)
                }
            }
        }
        return foundUnit && totalSeconds > 0 ? totalSeconds : nil
    }

    /// Parses CPU strings like "150m", "2", "0.5", "15%" into millicores.
    public static func parseCPUToMillicores(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed != "-" else { return nil }
        if trimmed.hasSuffix("m") {
            let numStr = String(trimmed.dropLast())
            return Double(numStr)
        }
        if trimmed.hasSuffix("%") {
            let numStr = String(trimmed.dropLast())
            return (Double(numStr) ?? 0) * 10
        }
        if let val = Double(trimmed) {
            return val * 1000.0
        }
        return nil
    }

    /// Parses Memory / Storage strings like "128Mi", "1Gi", "512Ki", "2G" into bytes.
    public static func parseMemoryToBytes(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed != "-" else { return nil }
        if trimmed.hasSuffix("ti") {
            let num = Double(trimmed.dropLast(2)) ?? 0
            return num * 1024 * 1024 * 1024 * 1024
        }
        if trimmed.hasSuffix("gi") {
            let num = Double(trimmed.dropLast(2)) ?? 0
            return num * 1024 * 1024 * 1024
        }
        if trimmed.hasSuffix("g") {
            let num = Double(trimmed.dropLast(1)) ?? 0
            return num * 1000 * 1000 * 1000
        }
        if trimmed.hasSuffix("mi") {
            let num = Double(trimmed.dropLast(2)) ?? 0
            return num * 1024 * 1024
        }
        if trimmed.hasSuffix("m") {
            let num = Double(trimmed.dropLast(1)) ?? 0
            return num * 1000 * 1000
        }
        if trimmed.hasSuffix("ki") {
            let num = Double(trimmed.dropLast(2)) ?? 0
            return num * 1024
        }
        if trimmed.hasSuffix("k") {
            let num = Double(trimmed.dropLast(1)) ?? 0
            return num * 1000
        }
        if trimmed.hasSuffix("%") {
            let num = Double(trimmed.dropLast(1)) ?? 0
            return num * 1024 * 1024 * 100
        }
        return Double(trimmed)
    }

    /// Parses Ready fraction like "1/1", "0/1", "3/4" into fraction (0.0 .. 1.0) and ready count.
    public static func parseReadyRatio(_ text: String) -> (ready: Int, total: Int, ratio: Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/")
        if parts.count == 2, let r = Int(parts[0]), let t = Int(parts[1]) {
            let ratio = t > 0 ? Double(r) / Double(t) : 0
            return (r, t, ratio)
        }
        return nil
    }

    /// Compares two cell values intelligently for a given column key.
    public static func compare(key: String, a: String, b: String) -> ComparisonResult {
        let normKey = key.lowercased()

        // 1. Age
        if normKey == "age" {
            let secA = parseAgeToSeconds(a) ?? -1
            let secB = parseAgeToSeconds(b) ?? -1
            if secA != secB {
                return secA < secB ? .orderedAscending : .orderedDescending
            }
        }

        // 2. Ready
        if normKey == "ready" {
            if let rA = parseReadyRatio(a), let rB = parseReadyRatio(b) {
                if rA.ratio != rB.ratio {
                    return rA.ratio < rB.ratio ? .orderedAscending : .orderedDescending
                }
                if rA.ready != rB.ready {
                    return rA.ready < rB.ready ? .orderedAscending : .orderedDescending
                }
            }
        }

        // 3. CPU
        if normKey.contains("cpu") {
            let cpuA = parseCPUToMillicores(a) ?? -1
            let cpuB = parseCPUToMillicores(b) ?? -1
            if cpuA != cpuB {
                return cpuA < cpuB ? .orderedAscending : .orderedDescending
            }
        }

        // 4. Memory / Storage / Disk
        if normKey.contains("memory") || normKey.contains("storage") || normKey.contains("disk") {
            let memA = parseMemoryToBytes(a) ?? -1
            let memB = parseMemoryToBytes(b) ?? -1
            if memA != memB {
                return memA < memB ? .orderedAscending : .orderedDescending
            }
        }

        // 5. Restarts / Available / Count / Replicas / Revision / Labels
        if normKey == "restarts" || normKey == "available" || normKey == "revision" || normKey == "labels" {
            let numA = Double(a.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "") ?? -1
            let numB = Double(b.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "") ?? -1
            if numA != numB {
                return numA < numB ? .orderedAscending : .orderedDescending
            }
        }

        // 6. Generic numbers (e.g. "$12.45" or "100")
        let cleanA = a.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        let cleanB = b.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        if let dA = Double(cleanA), let dB = Double(cleanB) {
            if dA != dB {
                return dA < dB ? .orderedAscending : .orderedDescending
            }
        }

        // 7. Fallback string localized standard compare
        return a.localizedStandardCompare(b)
    }

    /// Whether this column typically prefers descending order on first click (e.g. highest spend, oldest age, largest memory).
    public static func prefersDescendingDefault(key: String) -> Bool {
        let norm = key.lowercased()
        return norm == "age"
            || norm.contains("cpu")
            || norm.contains("memory")
            || norm.contains("storage")
            || norm.contains("disk")
            || norm.contains("spend")
            || norm.contains("cost")
            || norm.contains("run")
            || norm == "restarts"
            || norm == "available"
            || norm == "efficiency"
    }
}

// MARK: - Interactive Column Resize Divider Handle

public struct CTXColumnResizeDivider: View {
    let onDelta: (CGFloat) -> Void
    let onReset: () -> Void

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var lastDragX: CGFloat = 0

    public init(onDelta: @escaping (CGFloat) -> Void, onReset: @escaping () -> Void) {
        self.onDelta = onDelta
        self.onReset = onReset
    }

    public var body: some View {
        ZStack {
            // Visual thin line
            Rectangle()
                .fill(isHovered || isDragging ? Color.accentColor : Color.primary.opacity(0.12))
                .frame(width: isHovered || isDragging ? 2 : 1)

            // Invisible wider hit-target for easy grabbing
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 10)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else if !isDragging {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        lastDragX = value.startLocation.x
                    }
                    let delta = value.location.x - lastDragX
                    lastDragX = value.location.x
                    onDelta(delta)
                }
                .onEnded { _ in
                    isDragging = false
                    if !isHovered {
                        NSCursor.pop()
                    }
                }
        )
        .onTapGesture(count: 2) {
            onReset()
        }
        .help("Drag to resize column. Double-click to reset width.")
    }
}
