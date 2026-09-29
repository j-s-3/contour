import SwiftUI

struct DecisionChoiceView: View {
    let decisionId: String
    let brief: DecisionBrief

    var body: some View {
        switch brief.shape {
        case .binary?: binary
        case .threshold?: threshold
        case .options?: optionList
        case .beforeAfter?: beforeAfter
        case nil: answerLines
        }
    }

    private var binary: some View {
        let a = brief.options[0]
        let b = brief.options[1]
        return VStack(spacing: 7) {
            HStack(alignment: .bottom) {
                label(a, index: 0).frame(maxWidth: .infinity, alignment: .leading)
                label(b, index: 1).frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(spacing: 0) {
                dot(a)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 2)
                dot(b)
            }
            HStack(alignment: .top) {
                caption(a, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                caption(b, alignment: .trailing).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: 640)
    }

    private var threshold: some View {
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(brief.options.enumerated()), id: \.offset) { index, option in
                let connector = DecisionsViewLogic.connectorOpacities(index: index, count: brief.options.count)
                VStack(spacing: 7) {
                    label(option, index: index, alignment: .center)
                        .frame(height: 36, alignment: .bottom)
                    ZStack {
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.secondary.opacity(connector.leading))
                            Rectangle().fill(Color.secondary.opacity(connector.trailing))
                        }
                        .frame(height: 2)
                        dot(option)
                    }
                    caption(option, alignment: .center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 680)
    }

    private var optionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(brief.options.enumerated()), id: \.offset) { index, option in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: option.chosen ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(option.chosen ? Color.accentColor : Color.secondary)
                    Text(option.label)
                        .font(.body.weight(option.chosen ? .semibold : .regular))
                        .foregroundStyle(option.chosen ? .primary : .secondary)
                    if let detail = option.detail {
                        Text(detail).font(.callout).foregroundStyle(.tertiary)
                    }
                    if option.chosen { chosenTag }
                }
                .contentShape(Rectangle())
                .reviewContextMenu(.decisionOption(decisionId: decisionId, index: index))
            }
        }
    }

    private var beforeAfter: some View {
        let before = brief.options[0]
        let after = brief.options[1]
        return VStack(alignment: .leading, spacing: 10) {
            structure(before, index: 0, title: "BEFORE")
            structure(after, index: 1, title: "AFTER")
        }
    }

    private func structure(_ option: DecisionOption, index: Int, title: String) -> some View {
        let parts = DecisionsViewLogic.beforeAfterParts(from: option.label)
        let tint = option.chosen ? Color.accentColor : Color.secondary
        return HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(option.chosen ? Color.accentColor : Color.secondary)
                .frame(width: 52, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    if i > 0 {
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(tint.opacity(0.7))
                    }
                    Text(part)
                        .font(.callout.weight(option.chosen ? .medium : .regular))
                        .foregroundStyle(option.chosen ? .primary : .secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(tint.opacity(option.chosen ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5).strokeBorder(tint.opacity(option.chosen ? 0.45 : 0.25)))
                }
            }
            if let detail = option.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if option.chosen { chosenTag }
        }
        .contentShape(Rectangle())
        .reviewContextMenu(.decisionOption(decisionId: decisionId, index: index))
    }

    private var answerLines: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                chosenTag.gridColumnAlignment(.leading)
                Text(brief.answer).font(.body).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if let insteadOf = brief.insteadOf {
                GridRow {
                    Text("INSTEAD OF")
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                    Text(insteadOf).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .reviewContextMenu(.decision(decisionId))
    }

    private func label(_ option: DecisionOption, index: Int, alignment: TextAlignment = .leading) -> some View {
        Text(option.label.uppercased())
            .font(.callout.weight(option.chosen ? .bold : .medium))
            .tracking(0.4)
            .foregroundStyle(option.chosen ? .primary : .secondary)
            .multilineTextAlignment(DecisionsViewLogic.labelAlignment(alignment, index: index))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .help(
                option.chosen
                    ? "What this PR chose — right-click to ask why" : "Not chosen — right-click to ask about it"
            )
            .reviewContextMenu(.decisionOption(decisionId: decisionId, index: index))
    }

    @ViewBuilder
    private func dot(_ option: DecisionOption) -> some View {
        if option.chosen {
            Circle().fill(Color.accentColor).frame(width: 14, height: 14)
        } else {
            Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                .frame(width: 12, height: 12)
        }
    }

    private func caption(_ option: DecisionOption, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            if option.chosen { chosenTag }
            if let detail = option.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(
                        alignment == .trailing ? .trailing : (alignment == .center ? .center : .leading))
            }
        }
    }

    private var chosenTag: some View {
        Text("CHOSEN")
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(Color.accentColor)
    }
}

struct TradeoffSpectrum: View {
    let tradeoff: DecisionTradeoff

    var body: some View {
        let weight = tradeoff.chosenPosition
        let second = DecisionsViewLogic.favorsSecondDimension(weight)
        HStack(spacing: 10) {
            Text(tradeoff.dimensionA)
                .foregroundStyle(!second ? .primary : .secondary)
                .fontWeight(!second ? .medium : .regular)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1.5)
                        .padding(.horizontal, 6)
                    HStack {
                        Image(systemName: "arrowtriangle.left.fill")
                        Spacer()
                        Image(systemName: "arrowtriangle.right.fill")
                    }
                    .font(.system(size: 7))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: DecisionsViewLogic.knobOffset(trackWidth: geo.size.width, position: weight))
                }
                .frame(height: geo.size.height)
            }
            .frame(width: 150, height: 12)
            Text(tradeoff.dimensionB)
                .foregroundStyle(second ? .primary : .secondary)
                .fontWeight(second ? .medium : .regular)
        }
        .font(.callout)
        .lineLimit(1)
        .contentShape(Rectangle())
        .help(DecisionsViewLogic.tradeoffHelp(tradeoff))
    }
}
