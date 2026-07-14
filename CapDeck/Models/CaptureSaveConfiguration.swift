import Foundation

struct CaptureSaveConfiguration: Equatable, Sendable {
    let format: ImageFormat
    let jpegQuality: Double
    let filenamePattern: String
    let folderBookmark: Data?
}
