import Foundation

struct TicketTextParser {
    func parse(lines recognizedLines: [RecognizedTextLine]) -> ParsedEventDetails {
        parse(textLines: recognizedLines.map(\.text), barcodePayloads: [])
    }

    func parse(lines recognizedLines: [RecognizedTextLine], barcodePayloads: [String]) -> ParsedEventDetails {
        parse(textLines: recognizedLines.map(\.text), barcodePayloads: barcodePayloads)
    }

    func parse(textLines: [String], barcodePayloads: [String] = []) -> ParsedEventDetails {
        let lines = textLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let rawText = lines.joined(separator: "\n")
        let joinedText = lines.joined(separator: " ")
        let seatingDetails = parseSeatingDetails(from: lines, joinedText: joinedText)

        return ParsedEventDetails(
            title: parseTitle(from: lines),
            date: parseDate(from: lines),
            venue: parseVenue(from: lines),
            section: seatingDetails.section,
            row: seatingDetails.row,
            seat: seatingDetails.seat,
            isGeneralAdmission: parseGeneralAdmission(in: joinedText),
            rawText: rawText,
            barcodePayloads: barcodePayloads
        )
    }

    private func parseTitle(from lines: [String]) -> String? {
        if let dateLineIndex = lines.firstIndex(where: { containsDateToken($0) }) {
            let candidatesBeforeDate = bestTitleCandidates(from: Array(lines.prefix(dateLineIndex)))
            if let title = candidatesBeforeDate.first {
                return title
            }
        }

        return bestTitleCandidates(from: lines).first
    }

    private func bestTitleCandidates(from lines: [String]) -> [String] {
        lines
            .filter { isLikelyTitleLine($0) }
            .sorted { lhs, rhs in
                let lhsScore = titleScore(lhs)
                let rhsScore = titleScore(rhs)
                if lhsScore == rhsScore {
                    return lhs.count > rhs.count
                }
                return lhsScore > rhsScore
            }
    }

    private func titleScore(_ line: String) -> Int {
        var score = min(line.count, 80)
        if line.contains(":") { score -= 8 }
        if line.range(of: #"^[A-Z0-9 &'.\-]+$"#, options: .regularExpression) != nil { score += 10 }
        if line.range(of: #"(?i)\b(vs\.?|at)\b"#, options: .regularExpression) != nil { score += 18 }
        if containsVenueKeyword(line) { score -= 20 }
        return score
    }

    private func isLikelyTitleLine(_ line: String) -> Bool {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalized.lowercased()

        guard normalized.count >= 3 else { return false }
        guard normalized.rangeOfCharacter(from: .letters) != nil else { return false }
        guard !isClockOnlyLine(normalized) else { return false }
        guard parseDate(from: [normalized]) == nil else { return false }

        let blockedFragments = [
            "ticketmaster", "apple wallet", "add to wallet", "view ticket", "mobile ticket",
            "barcode", "order", "account", "gate", "entry", "section", " sec ", "row",
            "seat", "date", "time", "venue", "admit", "price", "scan", "terms", "http",
            "www.", "stubhub", "ticket", "general admission"
        ]

        if blockedFragments.contains(where: { lower.contains($0) }) {
            return false
        }

        if normalized.range(of: #"^\$?\d+([.,]\d+)?$"#, options: .regularExpression) != nil {
            return false
        }

        return true
    }

    private func parseDate(from lines: [String]) -> Date? {
        let preferredTexts = preferredDateTexts(from: lines)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

        for text in preferredTexts {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = detector?.firstMatch(in: text, options: [], range: range), let date = match.date {
                return date
            }
        }

        return parseDateWithFormatters(from: preferredTexts)
    }

    private func preferredDateTexts(from lines: [String]) -> [String] {
        let dateLineIndices = lines.indices.filter { containsDateToken(lines[$0]) }
        guard !dateLineIndices.isEmpty else {
            return candidateWindows(from: lines).filter { !isClockOnlyLine($0) }
        }

        var texts: [String] = []

        for index in dateLineIndices {
            if let timeLine = nearestEventTimeLine(around: index, in: lines) {
                texts.append("\(lines[index]) \(timeLine)")
                texts.append("\(timeLine) \(lines[index])")
            }

            texts.append(lines[index])

            let start = max(lines.startIndex, index - 2)
            let end = min(lines.endIndex - 1, index + 2)
            if start <= end {
                texts.append(lines[start...end].joined(separator: " "))
            }
        }

        return Array(NSOrderedSet(array: texts)) as? [String] ?? texts
    }

    private func nearestEventTimeLine(around index: Int, in lines: [String]) -> String? {
        let searchIndices = lines.indices
            .filter { $0 != index && abs($0 - index) <= 4 }
            .sorted { abs($0 - index) < abs($1 - index) }

        return searchIndices
            .map { lines[$0] }
            .first(where: isEventTimeOnlyLine)
    }

    private func containsDateToken(_ text: String) -> Bool {
        let patterns = [
            #"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\b"#,
            #"\b\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\b"#,
            #"\b\d{4}-\d{1,2}-\d{1,2}\b"#
        ]

        return patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func isClockOnlyLine(_ text: String) -> Bool {
        text.range(of: #"(?i)^\s*\d{1,2}:\d{2}\s*(?:a\.?m\.?|p\.?m\.?)?\s*$"#, options: .regularExpression) != nil
    }

    private func isEventTimeOnlyLine(_ text: String) -> Bool {
        text.range(of: #"(?i)^\s*\d{1,2}:\d{2}\s*(?:a\.?m\.?|p\.?m\.?)\s*$"#, options: .regularExpression) != nil
    }

    private func candidateWindows(from lines: [String]) -> [String] {
        var windows = lines
        let maxWindowSize = min(3, lines.count)

        if maxWindowSize > 1 {
            for size in 2...maxWindowSize {
                for startIndex in 0...(lines.count - size) {
                    windows.append(lines[startIndex..<(startIndex + size)].joined(separator: " "))
                }
            }
        }

        windows.append(lines.joined(separator: " "))
        return windows
    }

    private func parseDateWithFormatters(from texts: [String]) -> Date? {
        let locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, MMM d, yyyy h:mm a",
            "EEE MMM d yyyy h:mm a",
            "MMM d, yyyy h:mm a",
            "MMMM d, yyyy h:mm a",
            "M/d/yyyy h:mm a",
            "M/d/yy h:mm a",
            "yyyy-MM-dd h:mm a",
            "EEE, MMM d, yyyy",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "M/d/yyyy",
            "M/d/yy",
            "yyyy-MM-dd"
        ]

        for text in texts {
            let cleaned = text
                .replacingOccurrences(of: #"(?i)\b(date|time|doors|event date)\b[: ]*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            for format in formats {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.dateFormat = format
                if let date = formatter.date(from: cleaned) {
                    return date
                }
            }
        }

        return nil
    }

    private func parseVenue(from lines: [String]) -> String? {
        for line in lines {
            if let explicit = capture(pattern: #"(?i)\b(?:venue|location)\b\s*[:\-]?\s*(.+)$"#, in: line) {
                return cleanValue(explicit)
            }
        }

        if let venueLine = lines.first(where: { line in
            containsVenueKeyword(line) && !isSeatLine(line) && parseDate(from: [line]) == nil
        }) {
            return cleanValue(venueLine)
        }

        if let dateIndex = lines.firstIndex(where: { parseDate(from: [$0]) != nil }) {
            let following = lines.dropFirst(dateIndex + 1).prefix(4)
            return following.first { line in
                isLikelyVenueFallback(line)
            }.map(cleanValue)
        }

        return nil
    }

    private func containsVenueKeyword(_ line: String) -> Bool {
        let lower = line.lowercased()
        let venueKeywords = [
            "arena", "stadium", "center", "centre", "theatre", "theater", "amphitheatre",
            "amphitheater", "field", "park", "hall", "club", "bowl", "auditorium", "pavilion"
        ]

        return venueKeywords.contains(where: lower.contains)
    }

    private func isLikelyVenueFallback(_ line: String) -> Bool {
        let lower = line.lowercased()
        guard line.rangeOfCharacter(from: .letters) != nil else { return false }
        guard !isSeatLine(line) else { return false }
        guard parseGeneralAdmission(in: line) == false else { return false }
        guard parseDate(from: [line]) == nil else { return false }
        return !["ticketmaster", "barcode", "order", "account", "gate", "entry"].contains { lower.contains($0) }
    }

    private func parseLabeledValue(labels: [String], in lines: [String], joinedText: String) -> String? {
        let labelPattern = labels
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = #"(?i)\b("# + labelPattern + #")(?:\.|\b)\s*(?:#|:|\-)?\s*([A-Z0-9][A-Z0-9\-/, ]{0,24})"#

        if let value = capture(pattern: pattern, in: joinedText, group: 2) {
            return cleanSeatValue(value)
        }

        for index in lines.indices {
            let normalized = lines[index]
                .lowercased()
                .replacingOccurrences(of: ".", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if labels.contains(normalized), index + 1 < lines.count {
                return cleanSeatValue(lines[index + 1])
            }
        }

        return nil
    }

    private func parseSeatingDetails(from lines: [String], joinedText: String) -> SeatingDetails {
        let tableDetails = parseColumnarSeatingDetails(from: lines)

        return SeatingDetails(
            section: tableDetails.section ?? parseLabeledValue(labels: ["sec", "section"], in: lines, joinedText: joinedText),
            row: tableDetails.row ?? parseLabeledValue(labels: ["row"], in: lines, joinedText: joinedText),
            seat: tableDetails.seat ?? parseLabeledValue(labels: ["seat", "seats"], in: lines, joinedText: joinedText)
        )
    }

    private func parseColumnarSeatingDetails(from lines: [String]) -> SeatingDetails {
        for index in lines.indices {
            let labels = seatingLabels(in: lines[index])
            if labels.count >= 2, let details = seatingDetails(for: labels, startingAt: index + 1, in: lines) {
                return details
            }

            var splitLabels: [SeatingLabel] = []
            var cursor = index
            while cursor < lines.endIndex, let label = seatingLabel(forWholeLine: lines[cursor]) {
                splitLabels.append(label)
                cursor += 1
            }

            if splitLabels.count >= 2, let details = seatingDetails(for: splitLabels, startingAt: cursor, in: lines) {
                return details
            }
        }

        return SeatingDetails()
    }

    private func seatingDetails(for labels: [SeatingLabel], startingAt startIndex: Int, in lines: [String]) -> SeatingDetails? {
        var values: [String] = []
        var cursor = startIndex

        while cursor < lines.endIndex, values.count < labels.count {
            let line = cleanValue(lines[cursor])

            if seatingLabel(forWholeLine: line) != nil || line.range(of: #"(?i)\b(entry info|ticket type|expired|barcode)\b"#, options: .regularExpression) != nil {
                break
            }

            let tokens = seatingValueTokens(in: line)
            if tokens.count >= labels.count - values.count {
                values.append(contentsOf: tokens.prefix(labels.count - values.count))
            } else if isLikelySeatingValue(line) {
                values.append(cleanSeatValue(line))
            }

            cursor += 1
        }

        guard values.count >= labels.count else {
            return nil
        }

        var details = SeatingDetails()
        for (label, value) in zip(labels, values) {
            details.set(value, for: label)
        }

        return details
    }

    private func seatingLabels(in line: String) -> [SeatingLabel] {
        normalizedWords(in: line).compactMap(SeatingLabel.init(rawValue:))
    }

    private func seatingLabel(forWholeLine line: String) -> SeatingLabel? {
        let words = normalizedWords(in: line)
        guard words.count == 1 else { return nil }
        return SeatingLabel(rawValue: words[0])
    }

    private func seatingValueTokens(in line: String) -> [String] {
        line
            .split { character in
                character.isWhitespace || [",", "|", "/", "\\"].contains(character)
            }
            .map(String.init)
            .filter(isLikelySeatingValue)
            .map(cleanSeatValue)
    }

    private func isLikelySeatingValue(_ value: String) -> Bool {
        let cleaned = cleanValue(value)
        guard !cleaned.isEmpty, cleaned.count <= 12 else { return false }
        guard cleaned.range(of: #"(?i)\b(entry|ticket|type|expired|info|barcode|resale)\b"#, options: .regularExpression) == nil else {
            return false
        }
        return cleaned.range(of: #"^[A-Z0-9][A-Z0-9\-]*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func normalizedWords(in line: String) -> [String] {
        line
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
    }

    private func parseGeneralAdmission(in text: String) -> Bool {
        let lower = text.lowercased()
        let patterns = [
            #"general\s+admission"#,
            #"\bga\b"#,
            #"standing\s+room"#,
            #"standing\s+only"#,
            #"floor\s+ga"#
        ]

        return patterns.contains { pattern in
            lower.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func isSeatLine(_ line: String) -> Bool {
        line.range(of: #"(?i)\b(sec|section|row|seat|seats|gate|portal)\b"#, options: .regularExpression) != nil
    }

    private func capture(pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > group else {
            return nil
        }

        let matchRange = match.range(at: group)
        guard let swiftRange = Range(matchRange, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private func cleanSeatValue(_ value: String) -> String {
        cleanValue(value)
            .replacingOccurrences(of: #"(?i)\b(row|seat|seats|sec|section|gate|entry|portal)\b.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":|-")))
    }
}

private struct SeatingDetails {
    var section: String?
    var row: String?
    var seat: String?

    mutating func set(_ value: String, for label: SeatingLabel) {
        switch label {
        case .section:
            section = value
        case .row:
            row = value
        case .seat:
            seat = value
        }
    }
}

private enum SeatingLabel {
    case section
    case row
    case seat

    init?(rawValue: String) {
        switch rawValue {
        case "sec", "section":
            self = .section
        case "row":
            self = .row
        case "seat", "seats":
            self = .seat
        default:
            return nil
        }
    }
}
