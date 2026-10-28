import Foundation
import Testing
@testable import PullBullKit

private func searches(_ count: Int) -> SavedSearches {
    var saved = SavedSearches()
    for n in 1...count { saved.add(name: "s\(n)", query: "q\(n)") }
    return saved
}

@Suite struct SavedSearchValidationTests {
    @Test func nameIsTrimmedAndOneToFortyCharacters() {
        #expect(SavedSearch.validName("  Bugs  ") == "Bugs")
        #expect(SavedSearch.validName("   ") == nil)
        #expect(SavedSearch.validName("") == nil)
        #expect(SavedSearch.validName(String(repeating: "a", count: 40))?.count == 40)
        #expect(SavedSearch.validName(String(repeating: "a", count: 41)) == nil)
        // Characters, not UTF-16 units: forty emoji fit.
        #expect(SavedSearch.validName(String(repeating: "🐞", count: 40)) != nil)
    }

    @Test func queryIsTrimmedAndNonEmpty() {
        #expect(SavedSearch.validQuery("  ~bug @alice ") == "~bug @alice")
        #expect(SavedSearch.validQuery(" \n ") == nil)
        // Stored as typed: case and inner spacing kept.
        #expect(SavedSearch.validQuery("Is:Open  login") == "Is:Open  login")
    }

    @Test func validatedTrimsBoth() {
        let id = UUID()
        #expect(SavedSearch.validated(id: id, name: " Mine ", query: " @me ")
            == SavedSearch(id: id, name: "Mine", query: "@me"))
        #expect(SavedSearch.validated(id: id, name: "", query: "@me") == nil)
        #expect(SavedSearch.validated(id: id, name: "Mine", query: "") == nil)
    }

    @Test func defaultNameIsTheQueryCappedAtForty() {
        #expect(SavedSearch.defaultName(for: " ~bug is:open ") == "~bug is:open")
        let long = String(repeating: "x", count: 50)
        #expect(SavedSearch.defaultName(for: long) == String(repeating: "x", count: 40))
    }

    @Test func cappedNameStopsAtForty() {
        #expect(SavedSearch.capped(String(repeating: "a", count: 45)).count == 40)
        #expect(SavedSearch.capped("short") == "short")
    }

    @Test func fieldTextEndsWithASpace() {
        #expect(SavedSearch(name: "Bugs", query: "~bug").fieldText == "~bug ")
    }

    @Test func accessibilityLabel() {
        #expect(SavedSearch(name: "Bugs", query: "~bug is:open").accessibilityLabel
            == "Bugs, saved search, ~bug is:open")
    }

    /// A name left as its query would only say it twice.
    @Test func accessibilityLabelOfAQueryNamedSearch() {
        let search = SavedSearch(name: "~bug is:open", query: "~bug is:open")
        #expect(search.nameIsQuery)
        #expect(search.accessibilityLabel == "~bug is:open, saved search")
        #expect(!SavedSearch(name: "Bugs", query: "~bug").nameIsQuery)
    }
}

@Suite struct SavedSearchesTests {
    @Test func addValidatesAndAppends() {
        var saved = SavedSearches()
        let bugs = saved.add(name: " Bugs ", query: " ~bug ")
        #expect(bugs?.name == "Bugs")
        let unnamed = saved.add(name: "", query: "~bug")
        #expect(unnamed == nil)
        let empty = saved.add(name: "Empty", query: "  ")
        #expect(empty == nil)
        // Duplicate names and queries are the owner's call.
        let again = saved.add(name: "Bugs", query: "~bug")
        #expect(again != nil)
        #expect(saved.items.map(\.query) == ["~bug", "~bug"])
    }

    @Test func updateKeepsTheLastValidValue() {
        var saved = SavedSearches()
        let bugs = saved.add(name: "Bugs", query: "~bug")!
        let renamed = saved.update(bugs.id, name: " Open bugs", query: "~bug is:open ")
        #expect(renamed)
        #expect(saved.items == [SavedSearch(id: bugs.id, name: "Open bugs", query: "~bug is:open")])
        let blankName = saved.update(bugs.id, name: "  ", query: "~bug")
        #expect(!blankName)
        let blankQuery = saved.update(bugs.id, name: "Bugs", query: "")
        #expect(!blankQuery)
        #expect(saved.items.first?.name == "Open bugs")
        #expect(saved.items.first?.query == "~bug is:open")
        let unknown = saved.update(UUID(), name: "x", query: "y")
        #expect(!unknown)
    }

    @Test func removeAndMove() {
        var saved = searches(4)
        let ids = saved.items.map(\.id)
        saved.move(fromOffsets: [0], toOffset: 3)
        #expect(saved.items.map(\.name) == ["s2", "s3", "s1", "s4"])
        saved.move(fromOffsets: [3], toOffset: 0)
        #expect(saved.items.map(\.name) == ["s4", "s2", "s3", "s1"])
        saved.move(fromOffsets: [1, 2], toOffset: 4)
        #expect(saved.items.map(\.name) == ["s4", "s1", "s2", "s3"])
        saved.remove(ids[1])
        #expect(saved.items.map(\.name) == ["s4", "s1", "s3"])
        saved.remove(UUID())
        #expect(saved.items.count == 3)
    }

    @Test func matchesTheTrimmedQueryCaseSensitively() {
        var saved = SavedSearches()
        saved.add(name: "Bugs", query: "~bug is:open")
        #expect(saved.contains(query: "~bug is:open"))
        #expect(saved.contains(query: "  ~bug is:open "))
        #expect(!saved.contains(query: "~Bug is:open"))
        #expect(!saved.contains(query: "~bug"))
        #expect(!saved.contains(query: ""))
        #expect(!SavedSearches().contains(query: "~bug"))
    }

    @Test func codableRoundTripIsAPlainArray() throws {
        let saved = searches(2)
        let data = try JSONEncoder().encode(saved)
        let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(array?.count == 2)
        #expect(array?.first?["name"] as? String == "s1")
        #expect(try JSONDecoder().decode(SavedSearches.self, from: data) == saved)
    }

    /// A malformed entry (missing field, wrong type) is dropped; the good ones around it load.
    @Test func decodingSkipsMalformedEntries() throws {
        let first = UUID(), last = UUID()
        let json = #"[{"id":"\#(first.uuidString)","name":"A","query":"a"},{"name":"No id","query":"x"},{"id":"\#(UUID().uuidString)","name":3,"query":"x"},"oops",{"id":"\#(last.uuidString)","name":"B","query":"b"}]"#
        let saved = try JSONDecoder().decode(SavedSearches.self, from: Data(json.utf8))
        #expect(saved.items == [
            SavedSearch(id: first, name: "A", query: "a"), SavedSearch(id: last, name: "B", query: "b"),
        ])
    }

    @Test func decodingDropsInvalidEntries() throws {
        let id = UUID()
        let json = #"[{"id":"\#(id.uuidString)","name":"Bugs","query":"~bug"},{"id":"\#(UUID().uuidString)","name":" ","query":"x"}]"#
        let saved = try JSONDecoder().decode(SavedSearches.self, from: Data(json.utf8))
        #expect(saved.items == [SavedSearch(id: id, name: "Bugs", query: "~bug")])
    }
}

@Suite struct SavedSearchEditorTests {
    @Test func rowsShowTheStoreWithTypedDrafts() {
        var saved = searches(2)
        var editor = SavedSearchEditor()
        let id = saved.items[0].id
        editor.edit(id, name: "Bugs ", query: "~bug", in: &saved)
        // The field keeps what was typed; the store holds it trimmed.
        #expect(editor.rows(in: saved)[0].name == "Bugs ")
        #expect(saved.items[0].name == "Bugs")
        #expect(editor.rows(in: saved)[1].name == "s2")
    }

    @Test func anInvalidEditKeepsTheLastValidValueAndRevertsOnClose() {
        var saved = searches(1)
        var editor = SavedSearchEditor()
        let id = saved.items[0].id
        editor.edit(id, name: "", query: "q1", in: &saved)
        let row = editor.rows(in: saved)[0]
        #expect(!row.nameIsValid && row.queryIsValid && !row.isValid)
        #expect(saved.items[0].name == "s1")
        editor.edit(id, name: "s1", query: " ", in: &saved)
        #expect(!editor.rows(in: saved)[0].queryIsValid)
        #expect(saved.items[0].query == "q1")
        editor.close()
        #expect(editor.rows(in: saved)[0] == SavedSearchEditor.Row(id: id, name: "s1", query: "q1"))
    }

    @Test func aNewRowIsStoredOnceValid() {
        var saved = searches(1)
        var editor = SavedSearchEditor()
        let id = editor.addRow()
        #expect(saved.items.count == 1)
        let rows = editor.rows(in: saved)
        #expect(rows.count == 2)
        #expect(rows[1] == SavedSearchEditor.Row(id: id, name: "New search", query: ""))
        #expect(!rows[1].isValid)
        // "+" again focuses the same unsaved row.
        let again = editor.addRow()
        #expect(again == id)
        #expect(editor.rows(in: saved).count == 2)
        editor.edit(id, name: "New search", query: "~bug", in: &saved)
        #expect(saved.items.map(\.id) == [saved.items[0].id, id])
        #expect(saved.items[1].query == "~bug")
        // Invalid again: the store keeps "~bug".
        editor.edit(id, name: "New search", query: "", in: &saved)
        #expect(saved.items[1].query == "~bug")
        #expect(editor.rows(in: saved).count == 2)
    }

    @Test func aNewRowThatNeverBecameValidIsDropped() {
        var saved = searches(1)
        var editor = SavedSearchEditor()
        let id = editor.addRow()
        editor.edit(id, name: "", query: "", in: &saved)
        editor.close()
        #expect(editor.rows(in: saved).map(\.id) == saved.items.map(\.id))
        #expect(saved.items.count == 1)
    }

    /// A focused field can push its text back after the tab closed: that edit is ignored until it opens.
    @Test func editsAfterCloseAreIgnoredUntilOpen() {
        var saved = searches(1)
        var editor = SavedSearchEditor()
        let id = saved.items[0].id
        editor.edit(id, name: "", query: "q1", in: &saved)
        editor.close()
        editor.edit(id, name: "", query: "q1", in: &saved)
        editor.edit(id, name: "Late", query: "q1", in: &saved)
        #expect(editor.rows(in: saved)[0] == SavedSearchEditor.Row(id: id, name: "s1", query: "q1"))
        #expect(saved.items[0].name == "s1")
        editor.open()
        editor.edit(id, name: "Renamed", query: "q1", in: &saved)
        #expect(saved.items[0].name == "Renamed")
    }

    @Test func deleteRemovesStoredAndUnsavedRows() {
        var saved = searches(2)
        var editor = SavedSearchEditor()
        let first = saved.items[0].id
        editor.edit(first, name: "", query: "q1", in: &saved)
        editor.delete(first, in: &saved)
        #expect(saved.items.map(\.name) == ["s2"])
        let new = editor.addRow()
        editor.delete(new, in: &saved)
        #expect(editor.rows(in: saved).map(\.name) == ["s2"])
    }

    /// The unsaved row stays last: it can't be dragged, and nothing drops below it.
    @Test func moveKeepsTheUnsavedRowLast() {
        var saved = searches(3)
        var editor = SavedSearchEditor()
        let new = editor.addRow()
        editor.move(fromOffsets: [0], toOffset: 4, in: &saved)
        #expect(saved.items.map(\.name) == ["s2", "s3", "s1"])
        #expect(editor.rows(in: saved).last?.id == new)
        editor.move(fromOffsets: [3], toOffset: 0, in: &saved)
        #expect(saved.items.map(\.name) == ["s2", "s3", "s1"])
        editor.move(fromOffsets: [2], toOffset: 0, in: &saved)
        #expect(saved.items.map(\.name) == ["s1", "s2", "s3"])
    }

    /// A search saved from the popover while Settings is open shows at once.
    @Test func rowsFollowTheStore() {
        var saved = searches(1)
        var editor = SavedSearchEditor()
        let new = editor.addRow()
        saved.add(name: "From popover", query: "@me")
        #expect(editor.rows(in: saved).map(\.name) == ["s1", "From popover", "New search"])
        #expect(editor.rows(in: saved).last?.id == new)
    }
}

@Suite struct SavedSearchApplyTests {
    @Test func applyingFillsTheFieldAndSearches() {
        var field = SearchFieldState()
        let saved = SavedSearch(name: "Open bugs", query: "~bug is:open")
        let query = field.apply(saved, people: .empty, labels: .empty)
        #expect(field.text == "~bug is:open ")
        #expect(field.searchCompletion == nil)
        #expect(query == SearchQuery.parse("~bug is:open "))
        #expect(query != .empty)
    }
}
