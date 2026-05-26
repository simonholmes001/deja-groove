import SwiftUI

#if canImport(UIKit)
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIImagePickerController

    let onImageCaptured: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImageCaptured: (Data) -> Void
        private let onCancel: () -> Void

        init(onImageCaptured: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onImageCaptured = onImageCaptured
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let imageData = image.jpegData(compressionQuality: 0.92) else {
                onCancel()
                return
            }

            onImageCaptured(imageData)
        }
    }
}
#endif
