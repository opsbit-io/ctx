import SwiftUI

/// A profile-detail row that preserves readable labels and values as the pane narrows.
struct ProfileDetailResponsiveRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                fieldLabel
                Spacer(minLength: 0)
                value()
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 5) {
                fieldLabel
                value()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .frame(minHeight: 38)
    }

    private var fieldLabel: some View {
        Text(label)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }
}
