// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchCardExpansionSupport {
    /// A lifted card stays inside the page, including on the smallest preset.
    static func frame(card: CGRect, page: CGSize, preferred: CGSize) -> CGRect {
        let margin = min(8, max(0, min(page.width, page.height) / 2))
        let width = min(max(0, page.width - margin * 2), max(card.width, preferred.width))
        let height = min(max(0, page.height - margin * 2), max(card.height, preferred.height))
        let x = min(max(margin, card.midX - width / 2), max(margin, page.width - margin - width))
        let y = min(max(margin, card.midY - height / 2), max(margin, page.height - margin - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func hoverScale(enabled: Bool, hovered: Bool, reduceMotion: Bool) -> CGFloat {
        enabled && hovered && !reduceMotion ? 1.022 : 1
    }
}
