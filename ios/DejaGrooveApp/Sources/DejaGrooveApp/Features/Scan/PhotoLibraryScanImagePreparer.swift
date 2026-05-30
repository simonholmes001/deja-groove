#if os(iOS)
import Foundation
import UIKit

enum PhotoLibraryScanImagePreparer {
    static func prepareForUpload(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: 0.9)
    }
}
#endif
