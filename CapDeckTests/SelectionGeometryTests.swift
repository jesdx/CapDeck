@testable import CapDeck
import CoreGraphics
import Testing

struct SelectionGeometryTests {
    @Test
    func normalizesDragInAnyDirection() {
        let rect = SelectionGeometry.normalizedRect(
            from: CGPoint(x: 90, y: 80),
            to: CGPoint(x: 10, y: 20)
        )

        #expect(rect == CGRect(x: 10, y: 20, width: 80, height: 60))
    }

    @Test
    func convertsBottomLeftRegionToScreenCaptureCoordinates() {
        let rect = SelectionGeometry.screenCaptureRect(
            from: CGRect(x: 50, y: 100, width: 300, height: 200),
            screenHeight: 900
        )

        #expect(rect == CGRect(x: 50, y: 600, width: 300, height: 200))
    }

    @Test
    func convertsQuartzWindowFrameToAppKitCoordinates() {
        let rect = SelectionGeometry.quartzRectToAppKit(
            CGRect(x: 40, y: 100, width: 500, height: 300),
            primaryScreenMaxY: 1080
        )

        #expect(rect == CGRect(x: 40, y: 680, width: 500, height: 300))
    }

    @Test
    func convertsLocalPointOnDisplayBelowPrimaryToQuartzCoordinates() {
        let point = SelectionGeometry.localAppKitPointToQuartz(
            CGPoint(x: 200, y: 300),
            displayQuartzFrame: CGRect(x: 0, y: 1080, width: 1512, height: 982)
        )

        #expect(point == CGPoint(x: 200, y: 1762))
    }

    @Test
    func convertsQuartzRectOnDisplayLeftOfPrimaryToLocalCoordinates() {
        let rect = SelectionGeometry.quartzRectToLocalAppKit(
            CGRect(x: -1000, y: 100, width: 400, height: 300),
            displayQuartzFrame: CGRect(x: -1080, y: 0, width: 1080, height: 1920)
        )

        #expect(rect == CGRect(x: 80, y: 1520, width: 400, height: 300))
    }
}
