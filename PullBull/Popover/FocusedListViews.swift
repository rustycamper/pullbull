import SwiftUI
import PullBullKit

/// The empty state of a list under a focus that hides items of the tab.
struct FocusedEmptyView: View {
    let model: AppModel
    let tabTitle: String
    /// Every item the focus hides, counted or not.
    let hiddenCount: Int

    var body: some View {
        let focus = model.listFocus
        ListStateView(
            symbol: model.timeFocus == nil ? "line.3.horizontal.decrease" : "clock",
            title: focus.emptyTitle(repoName: model.repoFocus.map { model.displayName(of: $0.repo) }, tabTitle: tabTitle)
        ) {
            HStack(spacing: 4) {
                if hiddenCount > 0 {
                    Text("\(focus.hiddenText(hiddenCount)) ·")
                        .foregroundStyle(.secondary)
                }
                Button("Show all") { model.clearFocus() }
                    .buttonStyle(.link)
            }
            .font(.system(size: 11))
        }
    }
}

/// "2 more in other repos · Show all" after the rows of a focused list; "2 hidden · Show all" with a time focus.
struct OtherReposLine: View {
    let model: AppModel
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(model.timeFocus == nil ? "\(count) more in other repos ·" : "\(model.listFocus.hiddenText(count)) ·")
                .foregroundStyle(.secondary)
            Button("Show all") { model.clearFocus() }
                .buttonStyle(.link)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .frame(height: 30)
        .padding(.top, 2)
    }
}
