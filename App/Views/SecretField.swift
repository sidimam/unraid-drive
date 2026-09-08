import SwiftUI

/// A secure text field with an eye button to reveal or hide its content.
struct SecretField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var monospaced = false
    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if revealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .focused($focused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.password)
            .font(monospaced ? .callout.monospaced() : .body)
            Button {
                revealed.toggle()
                // Keep the caret in the field when toggling.
                if focused { DispatchQueue.main.async { focused = true } }
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealed ? "Hide" : "Show")
        }
    }
}
