import SwiftUI
import PullBullKit

/// The Stats screen, pushed over the list or the search like a detail. The popover owns its keys.
struct StatsView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            Text(verbatim: String(describing: model.statsReport?.reviews.text))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            DetailBackButton(title: backTitle, action: model.closeStats)
            Spacer(minLength: 0)
        }
        // Centred on the whole bar, clear of the buttons on either side.
        .overlay {
            Text("Stats")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 96)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    private var backTitle: String {
        model.statsReturnsToSearch ? "Search" : model.selectedTabTitle
    }
}
