import Foundation
#if canImport(UIKit)
import UIKit
#endif

public protocol CameraAvailabilityChecking {
    var isAvailable: Bool { get }
}

public struct SystemCameraAvailability: CameraAvailabilityChecking {
    public init() {}

    public var isAvailable: Bool {
        #if canImport(UIKit)
        UIImagePickerController.isSourceTypeAvailable(.camera)
        #else
        return false
        #endif
    }
}

@MainActor
public final class ScanInputCoordinator: ObservableObject {
    @Published public var isSourceDialogPresented = false
    @Published public var isCameraPresented = false
    @Published public var isPhotoLibraryPresented = false

    public let isCameraAvailable: Bool

    public init(cameraAvailability: CameraAvailabilityChecking = SystemCameraAvailability()) {
        isCameraAvailable = cameraAvailability.isAvailable
    }

    public func handlePrimaryAction() {
        if isCameraAvailable {
            isSourceDialogPresented = true
        } else {
            isPhotoLibraryPresented = true
        }
    }

    public func chooseCamera() {
        isSourceDialogPresented = false
        isPhotoLibraryPresented = false
        isCameraPresented = true
    }

    public func choosePhotoLibrary() {
        isSourceDialogPresented = false
        isCameraPresented = false
        isPhotoLibraryPresented = true
    }

    public func dismissCamera() {
        isCameraPresented = false
    }
}
