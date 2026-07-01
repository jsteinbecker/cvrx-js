import Foundation
import SwiftUI


private struct DisabledGrayBorderedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.accentColor : Color.gray.opacity(0.65))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isEnabled ? Color.accentColor.opacity(0.10) : Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isEnabled ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.35))
            )
            .opacity(isEnabled ? 1 : 0.75)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
    }
}


extension Color {
    static let forestGreen = Color(red: 0.13, green: 0.36, blue: 0.22)
    static let aqua = Color(red: 0.00, green: 0.75, blue: 0.80)
    static let lilac = Color(red: 0.78, green: 0.64, blue: 0.86)
    static let crimson = Color(red: 0.86, green: 0.08, blue: 0.24)
}
