import Foundation

/// What the comment field held for an item when it was left.
public struct CommentDraft: Equatable, Sendable {
    public var text: String
    /// The caret as a UTF-16 offset into `text`.
    public var caret: Int

    public init(text: String, caret: Int) {
        self.text = text
        self.caret = caret
    }
}

/// Unsent comments, one per account and item, kept in memory for the session. Account changes keep them;
/// signing an account out drops its own.
public struct CommentDrafts: Equatable, Sendable {
    private struct Slot: Hashable, Sendable {
        let account: String
        let key: PRKey
    }

    private var drafts: [Slot: CommentDraft] = [:]

    public init() {}

    /// The draft for `key` under the login `account`, case ignored. Setting one with empty text removes it.
    public subscript(account account: String, key key: PRKey) -> CommentDraft? {
        get { drafts[Slot(account: account.lowercased(), key: key)] }
        set {
            let slot = Slot(account: account.lowercased(), key: key)
            drafts[slot] = newValue?.text.isEmpty == false ? newValue : nil
        }
    }

    /// Removes every draft of the login `login`, case ignored.
    public mutating func dropAccount(_ login: String) {
        let account = login.lowercased()
        drafts = drafts.filter { $0.key.account != account }
    }
}
