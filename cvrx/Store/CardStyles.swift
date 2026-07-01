import SwiftUI


enum CardStyle {
    static let cornerRadius: CGFloat = 16
    static let shadowRadius: CGFloat = 8
    static let shadowYOffset: CGFloat = 2
    static let shadowColor = Color.black.opacity(0.09)
    static let borderColor = Color.primary.opacity(0.08)
}

extension Color {
    static var rxGroupedBackground: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(.windowBackgroundColor)
        #endif
    }

    static var rxCardBackground: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(.controlBackgroundColor)
        #endif
    }
}

private struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                    .fill(Color.rxCardBackground)
                    .shadow(
                        color: CardStyle.shadowColor,
                        radius: CardStyle.shadowRadius,
                        x: 0,
                        y: CardStyle.shadowYOffset
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                    .strokeBorder(CardStyle.borderColor, lineWidth: 0.5)
            }
    }
}

extension View {
    func cardSurface() -> some View {
        modifier(CardSurface())
    }
}


struct CardHeader<Trailing: View>: View {
    let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .tracking(0.2)

            Spacer()

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

struct MetaPill: View {
    let systemImage: String
    let text: String
    var tone: Color = .secondary

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline.weight(.medium))
        } icon: {
            Image(systemName: systemImage)
                .font(.caption)
        }
        .foregroundStyle(tone)
    }
}
