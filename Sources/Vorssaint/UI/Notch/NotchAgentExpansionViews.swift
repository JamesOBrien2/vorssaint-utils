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
            HStack(spacing: 6) {
                Circle().fill(tint ?? .white.opacity(0.55)).frame(width: 6, height: 6)
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text((totals.unpriced == 0 ? "" : "≥ ") + AgentFormat.cost(totals.cost))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                NotchAgentExpandedLine(label: "Requests", value: "\(totals.requests)")
                NotchAgentExpandedLine(label: "Tokens", value: AgentFormat.tokens(totals.tokens.total))
            }
            if totals.tokens.prompt > 0 {
                HStack(spacing: 5) {
                    NotchAgentMeter(value: totals.tokens.prompt > 0
                                    ? Double(totals.tokens.output) / Double(totals.tokens.prompt + totals.tokens.output)
                                    : 0, tint: tint ?? .white, height: 4)
                    Text("Output \(AgentFormat.tokens(totals.tokens.output)) · Cache \(AgentFormat.percent(totals.tokens.cacheHitRate ?? 0))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            Text(value).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.9))
        }
    }
}

struct NotchAgentExpandedBucket: View {
    let title: String
    let totals: AgentTotals
    let peak: Double
    let tint: Color = .white

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 10, weight: .medium)).frame(width: 48, alignment: .leading)
            NotchAgentMeter(value: totals.weight(byCost: true) / max(peak, .leastNonzeroMagnitude),
                            tint: tint, height: 5)
            VStack(alignment: .trailing, spacing: 1) {
                Text(AgentFormat.cost(totals.cost)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(AgentFormat.tokens(totals.tokens.total)).font(.system(size: 8.5)).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}
