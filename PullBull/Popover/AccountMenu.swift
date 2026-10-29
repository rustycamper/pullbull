import AppKit
import PullBullKit

/// The footer's account menu: every account PullBull can read GitHub as (`AccountPicker.menu`), the current
/// one checked, each with the org it opens in; then Add Account… and Account Settings…. Choosing an account
/// switches to it as Settings › Account does, with its remembered org and board. A failed switch shows on
/// its own line the next time the menu opens.
@MainActor
enum AccountMenu {
    /// The menu on screen keeps its item target alive; menu items hold their target weakly.
    private static var activeTarget: MenuActionTarget?
    private static let avatarSize: CGFloat = 16

    /// Pops the menu up in `view` at `point`, with the current account positioned there.
    static func show(model: AppModel, in view: NSView, at point: NSPoint) {
        let target = MenuActionTarget()
        let menu = NSMenu()
        menu.autoenablesItems = false
        let signedOut = Set(model.authStates.compactMap { account, state in
            if case .signedOut = state { return account }
            return nil
        })
        let entries = AccountPicker.menu(
            appAccounts: model.appAccounts, ghLogins: model.accounts.map(\.login),
            current: model.settings.accountRef, currentOrg: model.settings.org,
            orgByAccount: model.settings.orgByAccount, signedOut: signedOut, canSignIn: model.canSignInWithGitHub)

        if let error = model.accountSwitchError {
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.toolTip = error
            menu.addItem(item)
            menu.addItem(.separator())
        }
        var positioned: NSMenuItem?
        for entry in entries {
            switch entry {
            case .account(let account, let detail, let isCurrent):
                let item = target.item(title: account.login) {
                    Task { await model.selectAccount(account) }
                }
                item.attributedTitle = title(account.login, detail: detail)
                item.state = isCurrent ? .on : .off
                item.image = avatar(account.login)
                // One switch at a time: the others wait for the one loading.
                item.isEnabled = !model.isSwitchingAccount
                if isCurrent { positioned = item }
                menu.addItem(item)
            case .header(let title):
                menu.addItem(.sectionHeader(title: title))
            case .separator:
                menu.addItem(.separator())
            case .addAccount:
                menu.addItem(target.item(title: "Add Account…") { model.showSignIn() })
            case .settings:
                menu.addItem(target.item(title: "Account Settings…") {
                    UserDefaults.standard.set(SettingsTab.account.rawValue, forKey: "settings.tab")
                    SettingsOpener.open()
                })
            }
        }

        activeTarget = target
        menu.popUp(positioning: positioned, at: point, in: view)
        // An item's action may be delivered after tracking ends; the target outlives it by a turn.
        DispatchQueue.main.async { if activeTarget === target { activeTarget = nil } }
    }

    /// "login  org", the org in the secondary colour.
    private static func title(_ login: String, detail: String?) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(string: login, attributes: [.font: font])
        if let detail {
            title.append(NSAttributedString(string: "  \(detail)", attributes: [
                .font: font, .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return title
    }

    /// The account's avatar, round, when it is already in memory (the footer shows the current one); none
    /// otherwise, so opening the menu never waits on the network.
    private static func avatar(_ login: String) -> NSImage? {
        guard let url = CachedAvatars.profileImageURL(login), let image = AvatarCache.shared.cachedImage(for: url)
        else { return nil }
        let size = NSSize(width: avatarSize, height: avatarSize)
        return NSImage(size: size, flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            image.draw(in: rect)
            return true
        }
    }
}
