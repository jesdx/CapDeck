@testable import CapDeck
import CoreGraphics
import Testing

struct CapturePixelSizingTests {
    @Test
    func doublesPointDimensionsForRetinaCapture() {
        let result = CapturePixelSizing.pixels(
            for: CGSize(width: 1512, height: 982),
            scale: 2
        )

        #expect(result == CGSize(width: 3024, height: 1964))
    }

    @Test
    func keepsNativeDimensionsForStandardDensityDisplay() {
        let result = CapturePixelSizing.pixels(
            for: CGSize(width: 1920, height: 1080),
            scale: 1
        )

        #expect(result == CGSize(width: 1920, height: 1080))
    }

    @Test
    func alignsFractionalRegionToPhysicalPixelsOnStandardDisplay() {
        let result = CapturePixelSizing.pixelAlignedSourceRect(
            CGRect(x: 289.5, y: 240.5, width: 1163, height: 833),
            within: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scale: 1
        )

        #expect(result == CGRect(x: 289, y: 240, width: 1164, height: 834))
    }

    @Test
    func alignsFractionalRegionToHalfPointsOnRetinaDisplay() {
        let result = CapturePixelSizing.pixelAlignedSourceRect(
            CGRect(x: 10.25, y: 20.25, width: 100, height: 80),
            within: CGRect(x: 0, y: 0, width: 1512, height: 982),
            scale: 2
        )

        #expect(result == CGRect(x: 10, y: 20, width: 100.5, height: 80.5))
        #expect(
            CapturePixelSizing.pixels(for: result.size, scale: 2)
                == CGSize(width: 201, height: 161)
        )
    }
}
