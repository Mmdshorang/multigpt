import XCTest
@testable import MultiCodex

final class MenuBarIconRendererTests: XCTestCase {
    func testRenderedIconUsesMenuBarTemplateSize() {
        let image = MenuBarIconRenderer.render(
            fiveHourPercent: 42,
            weeklyPercent: 17,
            isStale: false
        )

        XCTAssertEqual(image.size.width, 18)
        XCTAssertEqual(image.size.height, 18)
        XCTAssertFalse(image.isTemplate)
    }
}
