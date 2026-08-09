#if os(iOS)
import Foundation
import UIKit

enum PhotoLibraryScanImagePreparer {
    static func prepareForUpload(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return ScanImageUploadPreparer.prepareForUpload(image)
    }
}

enum ScanImageUploadPreparer {
    static let maxPixelDimension: CGFloat = 1024
    static let jpegCompressionQuality: CGFloat = 0.65

    static func prepareForUpload(_ image: UIImage) -> Data? {
        normalizedAndResized(image).jpegData(compressionQuality: jpegCompressionQuality)
    }

    private static func normalizedAndResized(_ image: UIImage) -> UIImage {
        let normalized = normalizedOrientation(image)
        let targetSize = resizedSize(for: normalized.size)
        guard targetSize != normalized.size else { return normalized }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func resizedSize(for size: CGSize) -> CGSize {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxPixelDimension else { return size }
        let scale = maxPixelDimension / longestSide
        return CGSize(
            width: round(size.width * scale),
            height: round(size.height * scale))
    }
}
#endif
