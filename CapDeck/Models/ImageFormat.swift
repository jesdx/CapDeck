import Foundation

enum ImageFormat: String, CaseIterable, Sendable {
    case png
    case jpeg

    var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}
