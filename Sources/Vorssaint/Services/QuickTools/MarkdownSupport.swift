// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MarkdownLineKind: Equatable {
    case heading(level: Int)
    case task(checked: Bool)
    case body
}

enum MarkdownStyleKind: Equatable {
    case headingMarker(level: Int)
    case headingText(level: Int)
    /// The leading "- " (or "* ") of a task line, hidden so only the box shows.
    case taskBullet
    case taskMarker(checked: Bool)
    case taskText(checked: Bool)
}

struct MarkdownStyleRun: Equatable {
    let range: NSRange
    let kind: MarkdownStyleKind
}

/// Small, source-preserving Markdown helpers for the Scratchpad editor.
///
/// This intentionally recognizes only the Markdown constructs that the
/// scratchpad renders interactively. The stored document remains ordinary
/// text, so unsupported Markdown is never rewritten or discarded.
enum MarkdownSupport {
    static func lineKind(_ line: String) -> MarkdownLineKind {
        if let heading = headingParts(in: line) {
            return .heading(level: heading.level)
        }
        if let task = taskParts(in: line) {
            return .task(checked: task.checked)
        }
        return .body
    }

    static func styleRuns(in text: String) -> [MarkdownStyleRun] {
        let document = text as NSString
        var runs: [MarkdownStyleRun] = []
        var lineStart = 0

        while lineStart < document.length {
            var lineEnd = 0
            var contentsEnd = 0
            document.getLineStart(nil,
                                  end: &lineEnd,
                                  contentsEnd: &contentsEnd,
                                  for: NSRange(location: lineStart, length: 0))
            let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let line = document.substring(with: lineRange)

            if let heading = headingParts(in: line) {
                runs.append(MarkdownStyleRun(
                    range: NSRange(location: lineStart, length: heading.markerLength),
                    kind: .headingMarker(level: heading.level)))
                if heading.textLength > 0 {
                    runs.append(MarkdownStyleRun(
                        range: NSRange(location: lineStart + heading.textStart,
                                       length: heading.textLength),
                        kind: .headingText(level: heading.level)))
                }
            } else if let task = taskParts(in: line) {
                if task.bulletLength > 0 {
                    runs.append(MarkdownStyleRun(
                        range: NSRange(location: lineStart + task.bulletStart,
                                       length: task.bulletLength),
                        kind: .taskBullet))
                }
                runs.append(MarkdownStyleRun(
                    range: NSRange(location: lineStart + task.markerStart,
                                   length: task.markerLength),
                    kind: .taskMarker(checked: task.checked)))
                if task.textLength > 0 {
                    runs.append(MarkdownStyleRun(
                        range: NSRange(location: lineStart + task.textStart,
                                       length: task.textLength),
                        kind: .taskText(checked: task.checked)))
                }
            }

            if lineEnd <= lineStart { break }
            lineStart = lineEnd
        }

        return runs
    }

    /// Returns the source range of a task marker containing the UTF-16 cursor
    /// location, if that location is on an interactive checkbox.
    static func markerRange(in text: String, at characterIndex: Int) -> NSRange? {
        guard characterIndex >= 0 else { return nil }
        for run in styleRuns(in: text) {
            guard case .taskMarker = run.kind else { continue }
            if characterIndex >= run.range.location && characterIndex < NSMaxRange(run.range) {
                return run.range
            }
        }
        return nil
    }

    /// Flips the task marker at a UTF-16 character location while preserving
    /// every other character in the document.
    static func toggled(in text: String, at characterIndex: Int) -> String? {
        guard let marker = markerRange(in: text, at: characterIndex) else { return nil }
        let source = text as NSString
        let markerText = source.substring(with: marker) as NSString
        guard markerText.length >= 3 else { return nil }

        let innerLength = markerText.length - 2
        let inner = markerText.substring(with: NSRange(location: 1, length: innerLength))
        let checked = inner == "x" || inner == "X"
        let replacement = checked ? "[ ]" : "[x]"
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: marker,
                                  with: replacement)
        return mutable as String
    }

    /// One indentation step for list lines: a tab, matching the key pressed.
    static let listIndent = "\t"
    /// Outdenting also removes up to this many leading spaces, for lists
    /// indented by hand or pasted from elsewhere.
    static let listOutdentSpaces = 4

    struct ListIndentEdit: Equatable {
        let range: NSRange
        let replacement: String
        /// The caret after the edit, kept on the same character it was on.
        let caret: Int
    }

    /// Tab and Shift-Tab on a bullet or task line move the whole line, marker
    /// included, when the caret sits in its indentation or marker ("- ",
    /// "* ", "+ ", "- [ ] "). Returns nil anywhere else, so Tab keeps its
    /// ordinary meaning inside the item's text.
    static func listIndentEdit(in text: String, caret: Int, outdent: Bool) -> ListIndentEdit? {
        let source = text as NSString
        guard caret >= 0, caret <= source.length else { return nil }
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        source.getLineStart(&lineStart,
                            end: &lineEnd,
                            contentsEnd: &contentsEnd,
                            for: NSRange(location: caret, length: 0))
        let line = source.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
        guard let prefixLength = listPrefixLength(in: line),
              caret - lineStart <= prefixLength else { return nil }

        if !outdent {
            return ListIndentEdit(range: NSRange(location: lineStart, length: 0),
                                  replacement: listIndent,
                                  caret: caret + (listIndent as NSString).length)
        }

        let lineSource = line as NSString
        var removed = 0
        if lineSource.length > 0, lineSource.character(at: 0) == 9 {
            removed = 1
        } else {
            while removed < min(listOutdentSpaces, lineSource.length),
                  lineSource.character(at: removed) == 32 {
                removed += 1
            }
        }
        guard removed > 0 else { return nil }
        return ListIndentEdit(range: NSRange(location: lineStart, length: removed),
                              replacement: "",
                              caret: max(lineStart, caret - removed))
    }

    /// The UTF-16 length of a list line's indentation and marker, through the
    /// spacing after it, or nil when the line is not a bullet or task.
    static func listPrefixLength(in line: String) -> Int? {
        if let task = taskParts(in: line) { return task.textStart }
        let source = line as NSString
        var bulletStart = 0
        while bulletStart < source.length, isMarkdownWhitespace(source.character(at: bulletStart)) {
            bulletStart += 1
        }
        guard bulletStart + 1 < source.length else { return nil }
        let bullet = source.character(at: bulletStart)
        guard bullet == 45 || bullet == 42 || bullet == 43,
              isMarkdownWhitespace(source.character(at: bulletStart + 1)) else { return nil }
        var contentStart = bulletStart + 2
        while contentStart < source.length, isMarkdownWhitespace(source.character(at: contentStart)) {
            contentStart += 1
        }
        return contentStart
    }

    private struct HeadingParts {
        let level: Int
        let markerLength: Int
        let textStart: Int
        let textLength: Int
    }

    private struct TaskParts {
        let checked: Bool
        let bulletStart: Int
        let bulletLength: Int
        let markerStart: Int
        let markerLength: Int
        let textStart: Int
        let textLength: Int
    }

    private static func headingParts(in line: String) -> HeadingParts? {
        let source = line as NSString
        guard source.length >= 2 else { return nil }

        var level = 0
        while level < source.length, source.character(at: level) == 35 {
            level += 1
        }
        guard (1...3).contains(level),
              level < source.length,
              isMarkdownWhitespace(source.character(at: level)) else { return nil }

        var textStart = level + 1
        while textStart < source.length, isMarkdownWhitespace(source.character(at: textStart)) {
            textStart += 1
        }
        return HeadingParts(level: level,
                            markerLength: level,
                            textStart: textStart,
                            textLength: source.length - textStart)
    }

    private static func taskParts(in line: String) -> TaskParts? {
        let source = line as NSString
        var bulletStart = 0
        while bulletStart < source.length, isMarkdownWhitespace(source.character(at: bulletStart)) {
            bulletStart += 1
        }
        guard bulletStart + 3 < source.length,
              source.character(at: bulletStart) == 45 || source.character(at: bulletStart) == 42,
              isMarkdownWhitespace(source.character(at: bulletStart + 1)),
              source.character(at: bulletStart + 2) == 91 else { return nil }

        let markerStart = bulletStart + 2
        var closingBracket = markerStart + 2
        while closingBracket < source.length, source.character(at: closingBracket) != 93 {
            let character = source.character(at: closingBracket)
            guard character == 32 || character == 120 || character == 88 else { return nil }
            closingBracket += 1
        }
        guard closingBracket < source.length else { return nil }

        let innerLength = closingBracket - markerStart - 1
        guard innerLength >= 1 else { return nil }
        let inner = source.substring(with: NSRange(location: markerStart + 1, length: innerLength))
        let checked = inner == "x" || inner == "X"
        let unchecked = inner.allSatisfy { $0 == " " }
        guard checked || unchecked else { return nil }

        let afterMarker = closingBracket + 1
        guard afterMarker == source.length
                || isMarkdownWhitespace(source.character(at: afterMarker)) else { return nil }
        var textStart = afterMarker
        while textStart < source.length, isMarkdownWhitespace(source.character(at: textStart)) {
            textStart += 1
        }
        return TaskParts(checked: checked,
                         bulletStart: bulletStart,
                         bulletLength: 2,
                         markerStart: markerStart,
                         markerLength: closingBracket - markerStart + 1,
                         textStart: textStart,
                         textLength: source.length - textStart)
    }

    private static func isMarkdownWhitespace(_ character: unichar) -> Bool {
        character == 32 || character == 9
    }
}
