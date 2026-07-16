@testable import CapDeck
import CoreGraphics
import Testing

struct CaptureThumbnailLayoutTests {
    @Test
    func sizesLandscapeThumbnailWithoutChangingAspectRatio() {
        let size = CaptureThumbnailLayout.size(
            imageSize: CGSize(width: 1920, height: 1080)
        )

        #expect(size == CGSize(width: 240, height: 135))
    }

    @Test
    func sizesPortraitThumbnailWithinTheMaximumHeight() {
        let size = CaptureThumbnailLayout.size(
            imageSize: CGSize(width: 1080, height: 1920)
        )

        #expect(size == CGSize(width: 90, height: 160))
    }

    @Test
    func anchorsThumbnailInsideTheBottomRightOfItsDisplay() {
        let origin = CaptureThumbnailLayout.origin(
            panelSize: CGSize(width: 260, height: 155),
            visibleFrame: CGRect(x: -1080, y: 24, width: 1080, height: 1896)
        )

        #expect(origin == CGPoint(x: -280, y: 44))
    }
}
