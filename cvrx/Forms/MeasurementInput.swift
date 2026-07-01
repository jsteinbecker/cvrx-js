import SwiftUI

/// A single-looking input field that binds the numeric magnitude while displaying
/// a locked, read-only unit label as part of the same control.
struct MeasurementInput: View {
    
    @Binding var magnitudeText: String
    @FocusState private var isFocused: Bool
    @State private var warningActive: Bool = false

    let unit: String
    var name: String = ""

    var body: some View {
        HStack(spacing: 0) {
            TextField(name, text: $magnitudeText)
                .focused($isFocused)
                .multilineTextAlignment(.trailing)
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 4))
                .font(.body)
                .foregroundColor(.primary)
                .disableAutocorrection(true)
                .frame(width: 54, alignment: .leading)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif

            Text(" \(unit)")
                .foregroundStyle(.secondary)
                .fixedSize()
                .onTapGesture { isFocused = true }
        }
        .padding(.horizontal, 8)
        .padding(.vertical,   4)
        .background {
            if (warningActive) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.orange.opacity(0.5))
            }
            else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.background)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: 1
                )
        }
    }
    
    func toggleWarning() {
        warningActive.toggle()
    }
}


#Preview {
    MeasurementInput(
        magnitudeText: .constant("150"),
        unit: "mg",
        name: "Fosaprepitant"
    )
}
