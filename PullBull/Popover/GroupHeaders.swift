import SwiftUI
import PullBullKit

/// Which context menus a group header offers: the list's (the repo focus or a search for the author,
/// Show Only Updated and Open All), or none.
enum HeaderMenus {
    case list, none
}

/// A repo group's header, counting what the tab counts; in a list it offers the repo focus.
struct RepoGroupHeader: View {
    let model: AppModel
    let repo: String
    let rows: [Row]
    let menus: HeaderMenus

    var body: some View {
        let count = rows.filter(\.counted).count
        let list = menus == .list
        ListSectionHeader(
            glyph: "book.closed", title: repo.split(separator: "/").last.map(String.init) ?? repo,
            count: count > 0 ? count : nil, compact: model.settings.compact)
            .focusContextMenu(
                list ? FocusMenuItem(model: model, repo: repo) : nil, time: list ? TimeFocusMenu(model: model) : nil,
                openAll: list ? BulkOpenItem(urls: rows.map(\.pr.url)) : nil)
    }
}

/// An author group's header: their avatar and login, counting what the tab counts; in a list it offers a
/// search for them.
struct AuthorGroupHeader: View {
    let model: AppModel
    let author: String
    let rows: [Row]
    let menus: HeaderMenus

    var body: some View {
        let count = rows.filter(\.counted).count
        let list = menus == .list
        ListSectionHeader(
            glyph: nil, title: author, count: count > 0 ? count : nil,
            avatar: .init(login: author, url: rows.first?.pr.authorAvatarURL), compact: model.settings.compact)
        .focusContextMenu(
            list ? FocusMenuItem.person(model: model, login: author) : nil, time: list ? TimeFocusMenu(model: model) : nil,
            openAll: list ? BulkOpenItem(urls: rows.map(\.pr.url)) : nil)
    }
}

extension IssueGroup {
    /// A repo group, whose header names the repo its rows are in.
    var isRepo: Bool {
        if case .repo = kind { return true }
        return false
    }
}

/// An Issues group's header: its Status, "No status", "Not on board" or repo, with the lane's fold.
struct IssueGroupHeader: View {
    let model: AppModel
    let group: IssueGroup
    /// A lane's fold; nil for headers that don't fold.
    let fold: ListSectionHeader.Fold?
    let menus: HeaderMenus

    /// Only a repo group's header offers the repo focus.
    private var focusItem: FocusMenuItem? {
        guard case .repo(let repo) = group.kind else { return nil }
        return FocusMenuItem(model: model, repo: repo)
    }

    var body: some View {
        let list = menus == .list
        ListSectionHeader(
            glyph: symbol, glyphColor: symbolColor, title: group.title,
            count: group.counted ? group.issues.count : nil, fold: fold, compact: model.settings.compact)
            .focusContextMenu(
                list ? focusItem : nil, time: list ? TimeFocusMenu(model: model) : nil, openAll: list ? openAll : nil)
    }

    /// Every lane and repo group offers it; the merged untitled group has no header.
    private var openAll: BulkOpenItem? {
        BulkOpenItem(urls: group.issues.map(\.url))
    }

    /// Status lanes take the owner's Status colour; the colour is decorative, the title names the status.
    private var symbolColor: Color {
        guard case .status(let option) = group.kind, let color = option.color else { return .secondary }
        return Palette.statusOptionColor(color)
    }

    private var symbol: String {
        switch group.kind {
        case .status(let option): return BoardStatusGlyph.symbol(forStatusNamed: option.name)
        case .noStatus: return "circle.dotted"
        case .notOnBoard: return BoardStatusGlyph.notOnBoard
        case .repo: return "book.closed"
        case .all: return "list.bullet"
        case .done: return "checkmark.circle"
        }
    }
}
