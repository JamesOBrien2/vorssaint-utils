// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Evaluates the numeric subset of Scratchpad calculation mode.
///
/// This layer deliberately has no UI or persistence concerns. It evaluates
/// each line in order, so later lines can refer to earlier answers without
/// changing the text the user wrote.
enum ScratchpadCalculationEvaluator {
    struct LineResult: Equatable {
        let source: String
        let value: Double?
        let variable: String?
    }

    struct Result: Equatable {
        let lines: [LineResult]
        let variables: [String: Double]
    }

    static func evaluate(_ source: String,
                         decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
                         groupingSeparator: String = Locale.current.groupingSeparator ?? ",",
                         locale: Locale = .current) -> Result {
        var variables: [String: Double] = [:]
        var previous: Double?
        var total = 0.0
        var count = 0
        var constants: [String: Double?] = [:]
        var results: [LineResult] = []

        for line in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                results.append(LineResult(source: line, value: nil, variable: nil))
                continue
            }

            let assignment = assignmentParts(in: trimmed)
            let expression = assignment?.expression ?? trimmed
            let expanded = substitute(expression, variables: variables,
                                       previous: previous, total: total, count: count,
                                       decimalSeparator: decimalSeparator)
            let value: Double?
            if let cached = constants[expanded] { value = cached }
            else {
                value = evaluateExpression(expanded,
                                           decimalSeparator: decimalSeparator,
                                           groupingSeparator: groupingSeparator,
                                           locale: locale)
                if !expanded.contains(where: { $0.isLetter || $0 == "_" }) {
                    constants.updateValue(value, forKey: expanded)
                }
            }
            let variable = assignment?.name.lowercased()
            if let value, value.isFinite {
                if let variable {
                    variables[variable] = value
                }
                previous = value
                total += value
                count += 1
            } else if let variable {
                variables.removeValue(forKey: variable)
            }
            results.append(LineResult(source: line, value: value, variable: variable))
        }

        return Result(lines: results, variables: variables)
    }

    private static func evaluateExpression(_ expression: String,
                                           decimalSeparator: String,
                                           groupingSeparator: String,
                                           locale: Locale) -> Double? {
        if let value = CommandBarMath.evaluate(expression,
                                                decimalSeparator: decimalSeparator,
                                                groupingSeparator: groupingSeparator,
                                                locale: locale)?.value {
            return value
        }
        // CommandBarMath intentionally rejects lone numbers in launcher
        // queries. A calculation line may validly be a literal or variable.
        return CommandBarMath.literalValue(expression, decimalSeparator: decimalSeparator,
                                           groupingSeparator: groupingSeparator)
    }

    private struct Assignment {
        let name: String
        let expression: String
    }

    private static func assignmentParts(in line: String) -> Assignment? {
        guard let match = assignmentPattern.firstMatch(
            in: line, range: NSRange(location: 0, length: (line as NSString).length)),
              match.numberOfRanges == 2 + 1 else { return nil }
        let value = line as NSString
        let name = value.substring(with: match.range(at: 1))
        let expression = value.substring(with: match.range(at: 2))
        return Assignment(name: name, expression: expression)
    }

    private static let assignmentPattern = try! NSRegularExpression(pattern: #"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$"#)

    private static func substitute(_ expression: String,
                                   variables: [String: Double],
                                   previous: Double?, total: Double, count: Int,
                                   decimalSeparator: String) -> String {
        let special: [String: Double?] = [
            "prev": previous,
            "sum": count == 0 ? nil : total,
            "avg": count == 0 ? nil : total / Double(count),
        ]
        let characters = Array(expression)
        var output = ""
        var index = 0
        while index < characters.count {
            guard isIdentifierStart(characters[index]) else {
                output.append(characters[index])
                index += 1
                continue
            }
            let start = index
            index += 1
            while index < characters.count, isIdentifierPart(characters[index]) {
                index += 1
            }
            let word = String(characters[start..<index])
            let name = word.lowercased()
            if !(start > 0 && (characters[start - 1].isNumber || characters[start - 1] == ".")),
               let value = variables[name] ?? special[name] ?? nil {
                output += localizedNumber(value, decimalSeparator: decimalSeparator)
            } else {
                output += word
            }
        }
        return output
    }

    private static func localizedNumber(_ value: Double, decimalSeparator: String) -> String {
        CommandBarMath.reusableExpression(for: .init(formatted: "", value: value, closingBrackets: ""),
                                          decimalSeparator: decimalSeparator)
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isASCII && character.isLetter
    }

    private static func isIdentifierPart(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }
}
