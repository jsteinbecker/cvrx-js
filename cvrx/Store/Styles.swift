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
