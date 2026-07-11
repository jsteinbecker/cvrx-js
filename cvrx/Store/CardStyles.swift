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

private struct RoundedPanelSurface: ViewModifier {
    let cornerRadius: CGFloat
    let fill: AnyShapeStyle
    let borderColor: Color
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: lineWidth)
            }
    }
}

extension View {
    func cardSurface() -> some View {
        modifier(CardSurface())
    }

    func roundedPanel<S: ShapeStyle>(
        cornerRadius: CGFloat = 8,
        fill: S,
        borderColor: Color = Color.primary.opacity(0.12),
        lineWidth: CGFloat = 1
    ) -> some View {
        modifier(
            RoundedPanelSurface(
                cornerRadius: cornerRadius,
                fill: AnyShapeStyle(fill),
                borderColor: borderColor,
                lineWidth: lineWidth
            )
        )
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

struct AcceptableNDCInfoButton: View {
    let productName: String
    let ndcs: [String]

    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
                .opacity(0.55)
        }
        .buttonStyle(.plain)
        .help("Show acceptable NDCs")
        .accessibilityLabel("Show acceptable NDCs for \(productName)")
        .popover(isPresented: $isShowingPopover) {
            AcceptableNDCPopover(productName: productName, ndcs: ndcs)
        }
    }
}

private struct AcceptableNDCPopover: View {
    let productName: String
    let ndcs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Acceptable NDCs")
                    .font(.subheadline.weight(.semibold))
                Text(productName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            if ndcs.isEmpty {
                Text("No acceptable NDCs linked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(ndcs.enumerated()), id: \.offset) { _, ndc in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.green)
                            Text(ndc)
                                .font(.caption.monospacedDigit())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
    }
}

struct PillLabel: View {
    let text: String
    var systemImage: String? = nil
    var tone: Color = .accentColor
    var foregroundStyle: Color? = nil
    var font: Font = .caption.weight(.semibold)
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 4
    var backgroundOpacity: Double = 0.15

    var body: some View {
        label
            .font(font)
            .foregroundStyle(foregroundStyle ?? tone)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Capsule().fill(tone.opacity(backgroundOpacity)))
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(text, systemImage: systemImage)
        } else {
            Text(text)
        }
    }
}

struct CurrentUserBadge: View {
    let user: User?

    var body: some View {
        if let user {
            HStack(spacing: 5) {
                Image(systemName: "person.crop.circle.badge.checkmark", variableValue: 1.0)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.green, Color.white, Color.gray)
                    .font(.system(size: 16, weight: .regular))
                Text(user.name)
            }
            .padding(5)
        }
    }
}

struct ImageUnavailablePlaceholder: View {
    var title = "No image available"
    var systemImage = "photo"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct InstructionBar: View {
    let systemImage: String
    let text: String
    var tone: Color
    var backgroundOpacity: Double = 0.08

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tone)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tone.opacity(backgroundOpacity))
    }
}

enum RecipeStepRowAccessory {
    case numberBadge
    case selectionIcon
}

struct RecipeStepRow: View {
    let index: Int
    let text: String
    let isCurrent: Bool
    var accessory: RecipeStepRowAccessory = .numberBadge
    var textFont: Font = .callout
    var horizontalPadding: CGFloat? = 16
    var verticalPadding: CGFloat = 12

    var body: some View {
        HStack(alignment: .top, spacing: accessorySpacing) {
            accessoryView

            VStack(alignment: .leading, spacing: 2) {
                if accessory == .selectionIcon {
                    Text("Step \(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(text)
                    .font(textFont)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if accessory == .selectionIcon {
                Spacer()
            }
        }
        .padding(.horizontal, horizontalPadding ?? 0)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
    }

    private var accessorySpacing: CGFloat {
        switch accessory {
        case .numberBadge: 12
        case .selectionIcon: 10
        }
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .numberBadge:
            RecipeStepNumberBadge(number: index + 1, isCurrent: isCurrent)
        case .selectionIcon:
            Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                .padding(.top, 2)
        }
    }
}

private struct RecipeStepNumberBadge: View {
    let number: Int
    let isCurrent: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.15))
                .frame(width: 26, height: 26)

            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(isCurrent ? .white : .secondary)
        }
    }
}
