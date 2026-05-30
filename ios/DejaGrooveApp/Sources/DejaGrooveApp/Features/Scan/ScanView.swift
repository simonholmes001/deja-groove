import SwiftUI
import PhotosUI

#if os(iOS)
public struct ScanView: View {
    @StateObject private var viewModel: ScanViewModel
    @StateObject private var inputCoordinator: ScanInputCoordinator
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedCandidateIndex: Int?

    public init(viewModel: ScanViewModel, inputCoordinator: ScanInputCoordinator = ScanInputCoordinator()) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _inputCoordinator = StateObject(wrappedValue: inputCoordinator)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan")
                .font(.largeTitle.bold())
            Text(viewModel.guidance)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                inputCoordinator.handlePrimaryAction()
            } label: {
                Text("Pick or Capture Cover")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Scan Source", isPresented: $inputCoordinator.isSourceDialogPresented) {
                if inputCoordinator.isCameraAvailable {
                    Button("Take Photo") {
                        inputCoordinator.chooseCamera()
                    }
                }
                Button("Choose from Library") {
                    inputCoordinator.choosePhotoLibrary()
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $inputCoordinator.isPhotoLibraryPresented, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    guard let item = newItem,
                          let data = try? await item.loadTransferable(type: Data.self),
                          let preparedData = PhotoLibraryScanImagePreparer.prepareForUpload(data) else {
                        await viewModel.handleSelectedImagePreparationFailure()
                        return
                    }
                    await viewModel.submitScan(imageData: preparedData)
                }
            }
            .sheet(isPresented: $inputCoordinator.isCameraPresented) {
                CameraCaptureView(
                    onImageCaptured: { data in
                        inputCoordinator.dismissCamera()
                        Task { await viewModel.submitScan(imageData: data) }
                    },
                    onCancel: {
                        inputCoordinator.dismissCamera()
                    }
                )
                .ignoresSafeArea()
            }

            switch viewModel.state {
            case .idle:
                Text("Take a clear photo to start.")
                qualityGuidance
            case .loading:
                ProgressView("Analyzing cover...")
            case .error(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).foregroundStyle(.red)
                    if viewModel.isLastErrorRetryable {
                        Button("Retry Scan") {
                            Task { await viewModel.retryLastScan() }
                        }
                    }
                }
            case .result(let response):
                ScanResultView(
                    response: response,
                    selectedCandidateIndex: $selectedCandidateIndex
                ) { candidate in
                    Task {
                        await viewModel.resolve(requestId: response.requestId, candidate: candidate)
                        selectedCandidateIndex = nil
                    }
                }
                if response.canAddToCollection {
                    Button("Add To My Crate") {
                        Task { await viewModel.addResultToCollection() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let collectionMessage = viewModel.collectionMessage {
                    Text(collectionMessage)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }

            Spacer()
        }
        .padding()
    }

    private var qualityGuidance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture tips")
                .font(.subheadline.bold())
            Text("Use bright light, avoid reflections, and fill most of the frame with the album cover.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScanResultView: View {
    let response: ScanResponse
    @Binding var selectedCandidateIndex: Int?
    let onResolve: (Album) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status: \(response.status)")
                .font(.headline)
            if let album = response.album {
                Text("\(album.artist) — \(album.title)")
            }
            if response.status == "ambiguous" {
                Text("Select the correct release:")
                    .font(.subheadline.bold())
                ForEach(Array(response.candidates.enumerated()), id: \.offset) { _, candidate in
                    Button {
                        if let index = response.candidates.firstIndex(of: candidate) {
                            selectedCandidateIndex = index
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(candidate.artist)
                                Text(candidate.title).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selectedCandidateIndex == response.candidates.firstIndex(of: candidate) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }

                Button("Resolve Selection") {
                    guard let selectedCandidateIndex,
                          response.candidates.indices.contains(selectedCandidateIndex) else { return }
                    onResolve(response.candidates[selectedCandidateIndex])
                }
                .disabled(selectedCandidateIndex == nil || !response.candidates.indices.contains(selectedCandidateIndex ?? -1))
            }
        }
        .onChange(of: response.requestId) { _, _ in
            selectedCandidateIndex = nil
        }
    }
}
#endif
