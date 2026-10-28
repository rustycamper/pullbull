import SwiftUI
import PullBullKit

/// The empty state of a list under a repo focus that hides items of the tab in other repositories.
struct FocusedEmptyView: View {
    let model: AppModel
    let repoName: String
    let tabTitle: String
    /// Every item in other repositories, counted or not.
    let hiddenCount: Int

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Palette.fill))
            Text("Nothing in \(repoName) on \(tabTitle)")
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            HStack(spacing: 4) {
                if hiddenCount > 0 {
                    Text("\(hiddenCount) in other repos ·")
                        .foregroundStyle(.secondary)
                }
                Button("Show all") { model.focus(on: nil) }
                    .buttonStyle(.link)
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }
}

/// "2 more in other repos · Show all" after the rows of a focused list.
struct OtherReposLine: View {
    let model: AppModel
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count) more in other repos ·")
                .foregroundStyle(.secondary)
            Button("Show all") { model.focus(on: nil) }
                .buttonStyle(.link)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .frame(height: 30)
        .padding(.top, 2)
    }
}
