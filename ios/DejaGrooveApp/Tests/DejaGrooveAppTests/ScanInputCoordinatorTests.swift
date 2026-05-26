import XCTest
@testable import DejaGrooveApp

@MainActor
final class ScanInputCoordinatorTests: XCTestCase {
    func testPrimaryActionPresentsSourceDialogWhenCameraIsAvailable() {
        let sut = ScanInputCoordinator(cameraAvailability: StubCameraAvailability(isAvailable: true))

        sut.handlePrimaryAction()

        XCTAssertTrue(sut.isSourceDialogPresented)
        XCTAssertFalse(sut.isCameraPresented)
        XCTAssertFalse(sut.isPhotoLibraryPresented)
    }

    func testPrimaryActionDirectlyOpensLibraryWhenCameraIsUnavailable() {
        let sut = ScanInputCoordinator(cameraAvailability: StubCameraAvailability(isAvailable: false))

        sut.handlePrimaryAction()

        XCTAssertFalse(sut.isSourceDialogPresented)
        XCTAssertFalse(sut.isCameraPresented)
        XCTAssertTrue(sut.isPhotoLibraryPresented)
    }

    func testChooseCameraPresentsCamera() {
        let sut = ScanInputCoordinator(cameraAvailability: StubCameraAvailability(isAvailable: true))

        sut.chooseCamera()

        XCTAssertFalse(sut.isSourceDialogPresented)
        XCTAssertTrue(sut.isCameraPresented)
        XCTAssertFalse(sut.isPhotoLibraryPresented)
    }

    func testChoosePhotoLibraryPresentsLibrary() {
        let sut = ScanInputCoordinator(cameraAvailability: StubCameraAvailability(isAvailable: true))

        sut.choosePhotoLibrary()

        XCTAssertFalse(sut.isSourceDialogPresented)
        XCTAssertFalse(sut.isCameraPresented)
        XCTAssertTrue(sut.isPhotoLibraryPresented)
    }
}

private struct StubCameraAvailability: CameraAvailabilityChecking {
    let isAvailable: Bool
}
