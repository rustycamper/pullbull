import AppKit
import PullBullKit

/// The repository menu of the repo focus: "All Repositories", then every repository with anything
/// listed, each with its Review count and open count. Type-select works on the repository names.
@MainActor
enum RepoMenu {
    /// The menu on screen keeps its item target alive; menu items hold their target weakly.
    private static var activeTarget: MenuActionTarget?
    /// The room between a name and its counts.
    private static let countsGap: CGFloat = 24

    /// Pops the menu up in `view` at `point`, with the item for `repo` (`owner/name`) positioned there;
    /// with no `repo` and no focus, "All Repositories" is; with no such item, the menu's top left is at
    /// `point`.
    static func show(model: AppModel, highlighting repo: String?, in view: NSView, at point: NSPoint) {
        let focus = model.repoFocus
        let choices = model.repoChoices
        let target = MenuActionTarget()
        let menu = NSMenu()
        menu.autoenablesItems = false

        let all = target.item(title: "All Repositories") { model.focus(on: nil) }
        all.state = focus == nil ? .on : .off
        menu.addItem(all)
        menu.addItem(.separator())

        let font = NSFont.menuFont(ofSize: 0)
        let countsFont = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
        let counts = choices.map(countsText)
        let names = choices.map { model.displayName(of: $0.repo) }
        let nameWidth = names.map { width(of: $0, font: font) }.max() ?? 0
        let countsWidth = counts.map { width(of: $0, font: countsFont) }.max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: ceil(nameWidth + countsGap + countsWidth))]

        var positioned: NSMenuItem? = repo == nil && focus == nil ? all : nil
        for (choice, (name, count)) in zip(choices, zip(names, counts)) {
            let isFocus = focus.map { same($0.repo, choice.repo) } ?? false
            // Choosing the checked repository keeps it (focusing is idempotent); "All Repositories" clears.
            let item = target.item(title: name) { model.focus(on: choice.repo) }
            item.state = isFocus ? .on : .off
            item.toolTip = choice.repo
            let title = NSMutableAttributedString(
                string: name, attributes: [.font: font, .paragraphStyle: paragraph])
            title.append(NSAttributedString(string: "\t\(count)", attributes: [
                .font: countsFont, .paragraphStyle: paragraph,
            ]))
            item.attributedTitle = title
            if let repo, same(repo, choice.repo) { positioned = item }
            menu.addItem(item)
        }

        activeTarget = target
        menu.popUp(positioning: positioned, at: point, in: view)
        // An item's action may be delivered after tracking ends; the target outlives it by a turn.
        DispatchQueue.main.async { if activeTarget === target { activeTarget = nil } }
    }

    /// "2 · 5": the Review count and the open count; "· 3" with nothing to review.
    private static func countsText(_ choice: RepoChoice) -> String {
        choice.reviewCount > 0 ? "\(choice.reviewCount) · \(choice.openCount)" : "· \(choice.openCount)"
    }

    private static func width(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }
}
