// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchAgentExpandedScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NotchAgentExpandedTotals: View {
    let title: String
    let totals: AgentTotals
    let byCost: Bool
    let text: NotchAgentStrings
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint ?? .white.opacity(0.9))
            HStack(spacing: 8) {
                NotchAgentExpandedLine(label: "Requests", value: "\(totals.requests)")
                NotchAgentExpandedLine(label: "Tokens", value: AgentFormat.tokens(totals.tokens.total))
                NotchAgentExpandedLine(label: "Cost", value: (totals.unpriced == 0 ? "" : "≥ ") + AgentFormat.cost(totals.cost))
            }
            if totals.tokens.prompt > 0 {
                Text("Input \(AgentFormat.tokens(totals.tokens.prompt)) · Output \(AgentFormat.tokens(totals.tokens.output)) · Cache \(AgentFormat.percent(totals.tokens.cacheHitRate ?? 0)) · Saved \(AgentFormat.cost(totals.savings))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 3)
    }
}

struct NotchAgentExpandedLine: View {
    let label: String
    let value: String
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(tint)
        }
    }
}
