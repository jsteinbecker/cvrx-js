import Foundation

enum CameraError: LocalizedError {
    case authorizationDenied
    case noCameraAvailable
    case cannotAddInput
    case cannotAddOutput
    case notConfigured
    case noPhotoData
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Camera access was denied. Enable camera access in Settings."
        case .noCameraAvailable:
            "No compatible camera was found."
        case .cannotAddInput:
            "The camera input could not be added to the capture session."
        case .cannotAddOutput:
            "The photo output could not be added to the capture session."
        case .notConfigured:
            "The camera session has not been configured."
        case .noPhotoData:
            "The camera returned no photo data."
        case .invalidImageData:
            "The selected image could not be processed."
        }
    }
}
