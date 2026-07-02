import SwiftUI

/// An explicit multi-line text area with a visible border and placeholder —
/// plain TextFields inside grouped Forms are hard to discover, especially on macOS.
struct PromptTextArea: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var minHeight: CGFloat = 76
    var maxHeight: CGFloat = 140

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.tertiary, lineWidth: 1)
        )
    }
}
