import CoreGraphics
import Foundation

// CGImage is immutable and Core Graphics supports concurrent reads. Treating
// the result as Sendable lets encoding and file I/O leave the main actor
// without copying the pixel buffer.
struct CaptureResult: @unchecked Sendable {
    let image: CGImage
    let displayID: CGDirectDisplayID
    let timestamp: Date

    var pixelWidth: Int { image.width }
    var pixelHeight: Int { image.height }
}
