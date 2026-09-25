import SwiftUI

extension View {
    /// Faceplate background and a quiet separator, for rows in Harbor lists.
    func harborListRow() -> some View {
        listRowBackground(HarborColor.faceplate)
            .listRowSeparatorTint(HarborColor.aluminumDark.opacity(0.5))
    }
}

/// Centred title and hint filling a panel that has nothing to list.
struct EmptyPanel: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(title)
                .font(HarborFont.title(16))
                .foregroundStyle(HarborColor.ivory)
            Text(message)
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension TimeInterval {
    /// `m:ss`, e.g. `4:03`. `0:00` for NaN or infinity.
    var clockText: String {
        guard isFinite else { return "0:00" }
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
