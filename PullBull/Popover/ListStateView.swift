import SwiftUI

/// The one empty, unavailable and error state of a list: a glyph in a circle, a title, an optional detail
/// and an optional action. `footer` holds anything quieter below them (a link, a hint).
struct ListStateView<Footer: View>: View {
    enum Tone {
        case neutral
        /// A failure or something missing: the glyph in amber.
        case warning

        fileprivate var glyph: Color { self == .warning ? Palette.amberGlyph : Color.secondary }
        fileprivate var fill: Color { self == .warning ? Palette.amberFill : Palette.fill }
    }

    /// The gray button under the text.
    struct Action {
        let title: String
        var symbol: String?
        var help: String?
        var disabled = false
        let perform: () -> Void
    }

    let symbol: String
    var tone = Tone.neutral
    let title: String
    var detail: String?
    var action: Action?
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 10) {
            Image(symbol: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(tone.glyph)
                .frame(width: 48, height: 48)
                .background(Circle().fill(tone.fill))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let detail {
                // At least two lines held, so the one-line "You cleared…" copy doesn't move the view.
                ZStack {
                    Text(verbatim: " \n ").hidden()
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
            }
            if let action {
                Button {
                    action.perform()
                } label: {
                    if let symbol = action.symbol {
                        Label(action.title, systemImage: symbol)
                    } else {
                        Text(action.title)
                    }
                }
                .buttonStyle(IssueStateButtonStyle())
                .disabled(action.disabled)
                .help(action.help ?? "")
                .padding(.top, 4)
            }
            footer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }
}

extension ListStateView where Footer == EmptyView {
    init(symbol: String, tone: Tone = .neutral, title: String, detail: String? = nil, action: Action? = nil) {
        self.init(symbol: symbol, tone: tone, title: title, detail: detail, action: action) { EmptyView() }
    }
}

/// The gray action button of the list states and the Board's unavailable screens.
struct IssueStateButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(ButtonLabelStyle())
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Palette.strongFill.opacity(configuration.isPressed ? 1.6 : 1)))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct ButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 11, weight: .medium))
            configuration.title
        }
    }
}
