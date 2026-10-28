import SwiftUI
import PullBullKit

/// The slim row at the top of every list: "▦ Roadmap ▾ · ▤ All repos ▾" on the Board tab, "▤ All repos ▾"
/// elsewhere, "▤ widgets ▾ ✕" with a repo focus. The board name opens the board menu (⌘⇧B), the repo
/// name the repository menu (⌘⇧F); ✕ clears the focus.
struct FilterBar: View {
    let model: AppModel
    let row: FilterRow
    /// The board name, for ⌘⇧B.
    let boardAnchor: MenuAnchor
    @State private var repoAnchor = MenuAnchor()

    var body: some View {
        HStack(spacing: 6) {
            if let board = row.boardTitle {
                boardPart(board)
                Text("·")
                    .foregroundStyle(Palette.tertiary)
                    .accessibilityHidden(true)
            }
            // When tight, the board name truncates first.
            repoPart.layoutPriority(1)
            if row.isFocused {
                Button { model.focus(on: nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show all repos")
                .accessibilityLabel("Clear repo filter")
            }
            Spacer(minLength: 8)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.leading, Metrics.listGutter)
        .padding(.trailing, 8)
        .frame(height: 26)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func boardPart(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 10, weight: .medium))
                .accessibilityHidden(true)
            Button { showBoardMenu() } label: {
                Text("\(title) ▾")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(MenuAnchorView(anchor: boardAnchor))
            .help("Change Board")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.boardSpokenLabel ?? "")
        .accessibilityAction(named: "Change Board") { showBoardMenu() }
    }

    /// The glyph in the accent colour and the name in primary while a focus narrows the list.
    private var repoPart: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(row.isFocused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            Button { showRepoMenu() } label: {
                Text("\(row.repoTitle) ▾")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(MenuAnchorView(anchor: repoAnchor))
            .help("Change Repository")
        }
        .foregroundStyle(row.isFocused ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.repoSpokenLabel(tally: tally))
        .accessibilityAction(named: "Change Repository") { showRepoMenu() }
    }

    /// "2 of 4 in Review": the focused and all counted items of the tab on screen. On an issue tab m is
    /// the tab's own count (the stale one after a failed fetch); nil without a focus and while it reads
    /// "–" (not loaded, failed with nothing kept, Board unavailable), whose own states show instead.
    private var tally: String? {
        guard let focus = model.repoFocus else { return nil }
        switch model.mode {
        case .pullRequests:
            let tab = model.selectedTab
            guard let contents = model.contents(of: tab) else { return nil }
            return FilterRow.tally(focus.scope(contents).contents.count, of: contents.count, in: tab.title)
        case .issues:
            let tab = model.selectedIssueTab
            guard let issueTabs = model.issueTabs, issueTabs.isLoaded(tab), let contents = issueTabs.contents(tab),
                  let total = issueTabs.count(tab).value
            else { return nil }
            return FilterRow.tally(focus.scope(contents).contents.count, of: total, in: tab.title)
        }
    }

    /// Each menu drops from its name, with the current choice over it as a pop-up button's item is.
    private func showRepoMenu() {
        guard let view = repoAnchor.view else { return }
        RepoMenu.show(model: model, highlighting: model.repoFocus?.repo, in: view, at: .zero)
    }

    private func showBoardMenu() {
        guard let view = boardAnchor.view else { return }
        BoardMenu.show(model: model, in: view, at: .zero)
    }
}
