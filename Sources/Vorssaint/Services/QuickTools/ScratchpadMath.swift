// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Inline calculation for the scratchpad editor: a line that ends in "=" is
/// answered in a transient preview instead of staying a dead end. The grammar
/// is the command bar's own (same arithmetic, same units, same number
/// formatting), plus the one thing the bar does not need: names.
///
///     guests: 5
///     guests + 3 =        → 8
///     20 cm to in =       → 7.87 in
///
/// A "name: number" line defines a value for the lines below it; later
/// definitions win. Everything stays ordinary text: the preview is computed
/// on demand and never written into the document, so notes and exports are
/// unchanged.
enum ScratchpadMath {
    /// The transient answer for the line starting at `lineStart`, or nil when
    /// that line is not a calculable "… =".
    static func result(in document: String,
                       upTo lineStart: Int,
                       locale: Locale = .current) -> String? {
        let source = document as NSString
        guard lineStart >= 0, lineStart <= source.length else { return nil }

        var lineEnd = 0
        var contentsEnd = 0
        source.getLineStart(nil,
                            end: &lineEnd,
                            contentsEnd: &contentsEnd,
                            for: NSRange(location: lineStart, length: 0))
        let line = source.substring(with: NSRange(location: lineStart,
                                                  length: contentsEnd - lineStart))
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.last == "=", trimmed.count > 1 else { return nil }
        let expression = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
        guard !expression.isEmpty else { return nil }

        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","

        // A conversion reads "20 cm to in"; plain arithmetic has no words.
        if let converted = CommandBarUnits.convert(expression,
                                                   decimalSeparator: decimalSeparator,
                                                   groupingSeparator: groupingSeparator,
                                                   locale: locale) {
            return converted.formatted
        }

        let environment = variables(in: document, upTo: lineStart)
        let substituted = substituting(environment, in: expression)
        guard let answer = CommandBarMath.evaluate(substituted,
                                                   decimalSeparator: decimalSeparator,
                                                   groupingSeparator: groupingSeparator,
                                                   locale: locale) else {
            return nil
        }
        return answer.formatted
    }

    /// The named values defined by "name: number" lines above `lineStart`.
    /// Later definitions override earlier ones; headings, tasks and prose
    /// never match, so definitions travel with the text without decorating it.
    static func variables(in document: String, upTo lineStart: Int) -> [String: Double] {
        let source = document as NSString
        let limit = min(lineStart, source.length)
        var environment: [String: Double] = [:]
        var scan = 0
        while scan < limit {
            var lineEnd = 0
            var contentsEnd = 0
            source.getLineStart(nil,
                                end: &lineEnd,
                                contentsEnd: &contentsEnd,
                                for: NSRange(location: scan, length: 0))
            let line = source.substring(with: NSRange(location: scan,
                                                      length: contentsEnd - scan))
            if let definition = definition(in: line) {
                environment[definition.name] = definition.value
            }
            if lineEnd <= scan { break }
            scan = lineEnd
        }
        return environment
    }

    // MARK: - Definitions

    /// Parses one "name : number" line. Whitespace around the colon is
    /// optional, the value may be signed and fractional, and anything else
    /// (headings, tasks, prose) is not a definition.
    private static func definition(in line: String) -> (name: String, value: Double)? {
        let characters = Array(line.trimmingCharacters(in: .whitespaces))
        var index = 0
        guard index < characters.count,
              characters[index].isLetter || characters[index] == "_" else { return nil }
        var name = ""
        while index < characters.count,
              characters[index].isLetter || characters[index].isNumber
                || characters[index] == "_" {
            name.append(characters[index])
            index += 1
        }
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count, characters[index] == ":" else { return nil }
        index += 1
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count else { return nil }

        var negative = false
        if characters[index] == "-" || characters[index] == "+" {
            negative = characters[index] == "-"
            index += 1
        }
        var integer = ""
        while index < characters.count, characters[index].isNumber {
            integer.append(characters[index])
            index += 1
        }
        var fraction = ""
        if index < characters.count, characters[index] == "." {
            index += 1
            while index < characters.count, characters[index].isNumber {
                fraction.append(characters[index])
                index += 1
            }
        }
        guard !integer.isEmpty || !fraction.isEmpty else { return nil }
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index == characters.count,
              let value = Double("\(integer).\(fraction)") else { return nil }
        return (name, negative ? -value : value)
    }

    // MARK: - Substitution

    /// Replaces defined names in the expression with their fixed-point values,
    /// leaving unknown words alone so the calculator can refuse them.
    private static func substituting(_ variables: [String: Double],
                                     in expression: String) -> String {
        guard !variables.isEmpty else { return expression }
        var result = ""
        let characters = Array(expression)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isLetter || character == "_" {
                var name = ""
                while index < characters.count,
                      characters[index].isLetter || characters[index].isNumber
                        || characters[index] == "_" {
                    name.append(characters[index])
                    index += 1
                }
                result += (variables[name].map(fixedPoint) ?? name)
            } else {
                result.append(character)
                index += 1
            }
        }
        return result
    }

    /// A value written for the calculator to read back exactly in any locale:
    /// fixed decimals, no exponent and no grouping separators.
    private static func fixedPoint(_ value: Double) -> String {
        var digits = String(format: "%.12f", value)
        if digits.contains(".") {
            while digits.hasSuffix("0") { digits.removeLast() }
            if digits.hasSuffix(".") { digits.removeLast() }
        }
        return digits
    }
}
