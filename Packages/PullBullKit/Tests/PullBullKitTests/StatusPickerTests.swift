import Foundation
import Testing
@testable import PullBullKit

private let todo = BoardStatusValue(optionId: "o1", name: "Todo")
private let doing = BoardStatusValue(optionId: "o2", name: "Doing")
private let options = [
    StatusOption(id: "o1", name: "Todo", color: .gray), StatusOption(id: "o2", name: "Doing", color: .yellow),
    StatusOption(id: "o3", name: "Review", color: .purple),
]

private func board(_ issues: [BoardIssue]) -> Snapshot {
    editSnapshot(board: issues, created: [editIssue(500)], options: options)
}

private let snap = board([
    editIssue(412, status: doing), editIssue(413, status: todo), editIssue(414, status: todo, isOpen: false),
])

private func picker(_ number: Int, in snapshot: Snapshot = snap) throws -> StatusPicker {
    try #require(StatusPicker.make(for: editKey(number), in: snapshot, permission: .ready))
}

@Suite struct StatusPickerTests {
    @Test func rowsInBoardOrderWithCountsThenClear() throws {
        let p = try picker(412)
        #expect(p.rows.map(\.id) == ["o1", "o2", "o3", "clear"])
        #expect(p.rows.map(\.openCount) == [1, 1, 0, nil])
        #expect(p.rows.map(\.isCurrent) == [false, true, false, false])
        #expect(p.rows[1].option?.color == .yellow)
        #expect(p.selection == 1)
    }

    @Test func noClearWithoutAStatus() throws {
        let p = try picker(500)
        #expect(p.rows.map(\.id) == ["o1", "o2", "o3"])
        #expect(!p.rows.contains { $0.isCurrent })
        #expect(p.selection == 0)
    }

    @Test func deletedCurrentOptionChecksNothing() throws {
        let p = try picker(412, in: board([editIssue(412, status: BoardStatusValue(optionId: "o9", name: "Gone"))]))
        #expect(!p.rows.contains { $0.isCurrent })
        #expect(p.selection == 0)
        #expect(p.rows.last?.id == "clear")
    }

    @Test func filterByPartOfTheNameIgnoringCase() throws {
        var p = try picker(412)
        p.setFilter("OIN")
        #expect(p.rows.map(\.id) == ["o2"])
        #expect(p.selection == 0)
        p.setFilter("cle")
        #expect(p.rows.map(\.id) == ["clear"])
        p.setFilter("")
        #expect(p.rows.map(\.id) == ["o1", "o2", "o3", "clear"])
        #expect(p.selection == 1)
        p.setFilter("e")
        #expect(p.rows.map(\.id) == ["o3", "clear"])
        #expect(p.selection == 0)
    }

    @Test func moveStopsAtTheEnds() throws {
        var p = try picker(500)
        p.move(by: -1)
        #expect(p.selection == 0)
        p.move(by: 10)
        #expect(p.selection == 2)
    }

    @Test func pickIsTheSelectedOptionOrClear() throws {
        var p = try picker(412)
        #expect(p.pick == .some(doing))
        p.move(by: 10)
        #expect(p.pick == .some(nil))
        p.setFilter("zzz")
        #expect(p.pick == nil)
    }

    @Test func notOfferedMakesNoPicker() {
        #expect(StatusPicker.make(for: PRKey(repo: "other/x", number: 1), in: snap, permission: .ready) == nil)
    }

    @Test func titleNamesTheIssue() throws {
        #expect(try picker(412).title == "o/r#412")
    }

    @Test func keepsThePermission() throws {
        let p = try #require(StatusPicker.make(
            for: editKey(412), in: snap, permission: .needsGhScope(command: "gh auth refresh -s project")))
        #expect(p.permission == .needsGhScope(command: "gh auth refresh -s project"))
    }
}
