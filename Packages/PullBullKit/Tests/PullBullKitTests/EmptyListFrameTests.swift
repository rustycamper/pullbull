import Testing
@testable import PullBullKit

@Suite struct EmptyListFrameTests {
    @Test func heights() {
        #expect(EmptyListFrame.height(sectionBelow: true) == 260)
        #expect(EmptyListFrame.height(sectionBelow: false) == 400)
    }
}
