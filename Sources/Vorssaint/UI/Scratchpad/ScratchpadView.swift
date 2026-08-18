// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The scratchpad card: a slim header, named tabs, the plain-text editor and a
/// quiet footer with copy, export and clear.
struct ScratchpadView: View {
    @ObservedObject private var service = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.scratchpadBackgroundOpacity) private var backgroundOpacity = 0.0
    @State private var copied = false
    @State private var dialog: ScratchpadDialog?
    @State private var renameDraft = ""

    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }
    private var isEmpty: Bool { service.text.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            editor
            footer
        }
        .background {
            ZStack {
                HUDBackdrop(cornerRadius: 14)
                Color(nsColor: .windowBackgroundColor)
                    .opacity(ScratchpadSupport.sanitizedBackgroundOpacity(backgroundOpacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .alert(dialogTitle, isPresented: dialogIsPresented) {
            switch dialog {
            case .rename(let pad):
                TextField(pad.name, text: $renameDraft)
                Button(text.cancel, role: .cancel) { dismissDialog() }
                Button(text.saveName) {
                    service.renamePad(pad.id, to: renameDraft)
                    dismissDialog()
                }
            case .close(let pad):
                Button(text.cancel, role: .cancel) { dismissDialog() }
                Button(text.closePad, role: .destructive) {
                    _ = service.closePad(pad.id)
                    dismissDialog()
                }
            case nil:
                EmptyView()
            }
        } message: {
            if case .close(let pad) = dialog {
                Text(String(format: text.deletePadMessageFormat, pad.name))
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(service.pads) { pad in
                            tabButton(pad)
                                .id(pad.id)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    guard let selected = service.selectedPadID else { return }
                    proxy.scrollTo(selected, anchor: .center)
                }
                .onChange(of: service.selectedPadID) { _, selected in
                    guard let selected else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
            }

            Button {
                service.createPad(defaultName: text.pageTitle)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!service.canCreatePad)
            .help(service.canCreatePad
                ? text.newPad
                : String(format: text.padLimitFormat, ScratchpadDocument.maximumPadCount))
            .accessibilityLabel(text.newPad)

            Menu {
                if let selectedPad {
                    Button(text.renamePad) { presentRename(selectedPad) }
                    Button(text.closePad, role: .destructive) { requestClose(selectedPad) }
                        .disabled(!service.canClosePad)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(text.padActions)
            .accessibilityLabel(text.padActions)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }

    private func tabButton(_ pad: ScratchpadPad) -> some View {
        let selected = service.selectedPadID == pad.id
        return Button {
            service.selectPad(pad.id)
        } label: {
            Text(pad.name)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 46, maxWidth: 120)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(text.renamePad) { presentRename(pad) }
            Button(text.closePad, role: .destructive) { requestClose(pad) }
                .disabled(!service.canClosePad)
        }
        .accessibilityLabel(pad.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var selectedPad: ScratchpadPad? {
        service.pads.first(where: { $0.id == service.selectedPadID })
    }

    private var dialogTitle: String {
        switch dialog {
        case .rename: return text.renamePad
        case .close: return text.closePad
        case nil: return ""
        }
    }

    private var dialogIsPresented: Binding<Bool> {
        Binding(
            get: { dialog != nil },
            set: { if !$0 { dismissDialog() } }
        )
    }

    private func presentRename(_ pad: ScratchpadPad) {
        renameDraft = pad.name
        dialog = .rename(pad)
        service.setModalInteractionActive(true)
    }

    private func requestClose(_ pad: ScratchpadPad) {
        guard service.canClosePad else { return }
        if !ScratchpadSupport.requiresCloseConfirmation(pad) {
            _ = service.closePad(pad.id)
        } else {
            dialog = .close(pad)
            service.setModalInteractionActive(true)
        }
    }

    private func dismissDialog() {
        dialog = nil
        service.setModalInteractionActive(false)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(text.pageTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay(ScratchpadDragHandle())
            Button {
                service.togglePin()
            } label: {
                Image(systemName: service.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(service.isPinned ? Color.accentColor : Color.secondary)
            .help(service.isPinned ? text.closeOnClickOutside : text.keepOpen)
            .accessibilityLabel(service.isPinned ? text.closeOnClickOutside : text.keepOpen)
            Button {
                ScratchpadService.shared.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuClose)
            .accessibilityLabel(l10n.s.menuClose)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var editor: some View {
        PlainTextEditor(text: $service.text)
            .overlay(alignment: .topLeading) {
                if isEmpty {
                    // NSTextView has no placeholder of its own; this sits at
                    // the exact spot of the first line and never takes clicks.
                    Text(text.placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 12)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
            }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            footerButton(copied ? "checkmark" : "doc.on.doc",
                         copied ? text.copied : text.copyAll,
                         tint: copied ? .green : nil) {
                service.copyAll()
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeOut(duration: 0.2)) { copied = false }
                }
            }
            footerButton("square.and.arrow.down", text.exportAction) {
                service.exportText(suggestedName:
                    ScratchpadSupport.exportFileName(title: service.selectedPadName, date: Date()))
            }
            Spacer()
            footerButton("trash", text.clearAction) {
                service.clear()
            }
        }
        .disabled(isEmpty)
        .opacity(isEmpty ? 0.5 : 1)
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private func footerButton(_ symbol: String,
                              _ label: String,
                              tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private enum ScratchpadDialog {
    case rename(ScratchpadPad)
    case close(ScratchpadPad)
}

/// A transparent strip over the header that moves the whole panel when
/// dragged; everything below it stays free for text selection.
private struct ScratchpadDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {}

    final class DragHandleView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// The editor keeps Markdown source in the text storage while applying
/// lightweight attributes on top. This gives the pad headings and task boxes
/// without introducing a second rendered document or changing exported text.
private final class MarkdownTextView: NSTextView {
    private let baseFont = NSFont.systemFont(ofSize: 13)
    /// The transient answer currently previewed for a line ending in "=";
    /// nil when no preview is showing.
    private var activePreview: String?
    private var isRepositioningPreview = false
    private lazy var resultLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        label.isHidden = true
        label.setAccessibilityElement(false)
        addSubview(label)
        return label
    }()

    func updateMarkdownAppearance() {
        guard let storage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        if fullRange.length > 0 {
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
            ], range: fullRange)
        }

        for run in MarkdownSupport.styleRuns(in: string) {
            switch run.kind {
            case .headingMarker(let level):
                storage.addAttributes(headingAttributes(level: level), range: run.range)
            case .headingText(let level):
                storage.addAttributes(headingAttributes(level: level), range: run.range)
            case .taskMarker(let checked):
                // Keep the three source characters in the document, but draw
                // one native-looking checkbox in place of their visible glyphs.
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: run.range)
                let attachment = NSTextAttachment()
                attachment.image = Self.checkboxImage(checked: checked)
                storage.addAttribute(.attachment,
                                      value: attachment,
                                      range: NSRange(location: run.range.location, length: 1))
            case .taskText(let checked):
                if checked {
                    storage.addAttributes([
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    ], range: run.range)
                }
            }
        }
        storage.endEditing()
        typingAttributes = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ]
        updateComputationPreview()
    }

    /// Recomputes and repositions the transient answer for the line under the
    /// caret, or hides it. The answer lives only in this label: the document
    /// keeps the "… = " the user typed, and Tab is what commits it.
    func updateComputationPreview() {
        let source = string as NSString
        let caret = selectedRange.location
        guard selectedRange.length == 0, caret <= source.length,
              let textContainer, let layoutManager else {
            hideComputationPreview()
            return
        }
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        source.getLineStart(&lineStart,
                            end: &lineEnd,
                            contentsEnd: &contentsEnd,
                            for: NSRange(location: caret, length: 0))
        guard let formatted = ScratchpadMath.result(in: string, upTo: lineStart) else {
            hideComputationPreview()
            return
        }
        activePreview = formatted

        layoutManager.ensureLayout(for: textContainer)
        let characterRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange,
                                                  actualCharacterRange: nil)
        let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange,
                                                  in: textContainer)
        resultLabel.stringValue = formatted
        resultLabel.sizeToFit()
        resultLabel.frame.origin = NSPoint(
            x: textContainerOrigin.x + lineRect.maxX + 6,
            y: textContainerOrigin.y + lineRect.minY
                + (lineRect.height - resultLabel.frame.height) / 2)
        resultLabel.isHidden = false
    }

    private func hideComputationPreview() {
        activePreview = nil
        resultLabel.isHidden = true
    }

    /// Tab accepts the preview into the note ("82 + 55 =" becomes
    /// "82 + 55 = 137"); anywhere else the tab keeps its ordinary meaning.
    override func insertTab(_ sender: Any?) {
        guard let preview = activePreview else {
            super.insertTab(sender)
            return
        }
        let source = string as NSString
        let caret = selectedRange.location
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        source.getLineStart(&lineStart,
                            end: &lineEnd,
                            contentsEnd: &contentsEnd,
                            for: NSRange(location: caret, length: 0))
        guard caret == contentsEnd else {
            super.insertTab(sender)
            return
        }
        insertText(" " + preview, replacementRange: selectedRange)
    }

    override func layout() {
        super.layout()
        guard !resultLabel.isHidden, !isRepositioningPreview else { return }
        isRepositioningPreview = true
        updateComputationPreview()
        isRepositioningPreview = false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        // The preview is decoration, not a control: clicks there belong to the
        // editor, which places the caret at the end of the expression line.
        return hit === resultLabel ? self : hit
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let task = taskMarker(at: point),
              let replacement = toggledMarker(in: string, range: task.range),
              shouldChangeText(in: task.range, replacementString: replacement) else {
            super.mouseDown(with: event)
            return
        }

        replaceCharacters(in: task.range, with: replacement)
        didChangeText()
        updateMarkdownAppearance()
    }

    private func taskMarker(at point: NSPoint) -> (range: NSRange, checked: Bool)? {
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x,
                                     y: point.y - textContainerOrigin.y)
        guard let layoutManager, let textContainer else { return nil }

        for run in MarkdownSupport.styleRuns(in: string) {
            guard case .taskMarker(let checked) = run.kind else { continue }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: run.range,
                                                       actualCharacterRange: nil)
            var bounds = layoutManager.boundingRect(forGlyphRange: glyphRange,
                                                    in: textContainer)
            bounds = bounds.insetBy(dx: -4, dy: -3)
            if bounds.contains(containerPoint) {
                return (run.range, checked)
            }
        }
        return nil
    }

    private func toggledMarker(in text: String, range: NSRange) -> String? {
        let source = text as NSString
        guard range.location >= 0, NSMaxRange(range) <= source.length else { return nil }
        guard let toggled = MarkdownSupport.toggled(in: text, at: range.location + 1),
              let newRange = MarkdownSupport.markerRange(in: toggled, at: range.location + 1) else {
            return nil
        }
        return (toggled as NSString).substring(with: newRange)
    }

    private func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let size: CGFloat
        let weight: NSFont.Weight
        let color: NSColor
        switch level {
        case 1:
            size = 18
            weight = .bold
            color = .controlAccentColor
        case 2:
            size = 15
            weight = .semibold
            color = .systemTeal
        default:
            size = 13.5
            weight = .semibold
            color = .secondaryLabelColor
        }
        return [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
    }

    private static func checkboxImage(checked: Bool) -> NSImage {
        let size = NSSize(width: 13, height: 13)
        let image = NSImage(size: size)
        image.lockFocus()
        let box = NSRect(x: 1, y: 1, width: 11, height: 11)
        if checked {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
            NSColor.white.setStroke()
            let check = NSBezierPath()
            check.lineWidth = 1.5
            check.move(to: NSPoint(x: 3.2, y: 6.4))
            check.line(to: NSPoint(x: 5.5, y: 3.8))
            check.line(to: NSPoint(x: 10, y: 9.2))
            check.stroke()
        } else {
            NSColor.secondaryLabelColor.setStroke()
            let path = NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
            path.lineWidth = 1.2
            path.stroke()
        }
        image.unlockFocus()
        return image
    }
}

/// An AppKit text view configured as a plain-text Markdown surface: no smart
/// quotes or dashes, no substitutions, no rich paste, with undo. SwiftUI's
/// editor cannot switch all of that off.
private struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        let textView = MarkdownTextView(frame: .zero)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 7, height: 2)
        textView.string = text
        textView.updateMarkdownAppearance()
        ScratchpadService.shared.registerTextView(textView)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownTextView else { return }
        guard textView.string != text, !textView.hasMarkedText() else { return }
        textView.string = text
        // Programmatic replaces (load, retention, restore) invalidate undo
        // entries recorded against the old storage; replaying one would
        // resurrect cleared text or throw a range exception.
        textView.undoManager?.removeAllActions()
        textView.updateMarkdownAppearance()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView,
                  !textView.hasMarkedText() else { return }
            textView.updateMarkdownAppearance()
            text.wrappedValue = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            textView.updateComputationPreview()
        }
    }
}
