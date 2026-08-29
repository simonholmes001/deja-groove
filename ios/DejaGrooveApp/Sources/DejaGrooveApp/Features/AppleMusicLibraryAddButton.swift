import SwiftUI

public enum DejaGrooveAppleMusicLibraryAdderFactory {
    public static func make() -> AppleMusicLibraryAdding {
        #if canImport(MusicKit) && os(iOS)
        return MusicKitAppleMusicLibraryAdder()
        #else
        return UnavailableAppleMusicLibraryAdder()
        #endif
    }
}

struct AppleMusicLibraryAddButton: View {
    let album: Album
    let libraryAdder: AppleMusicLibraryAdding

    @State private var isAdding = false
    @State private var hasAdded = false
    @State private var message: String?

    init(
        album: Album,
        libraryAdder: AppleMusicLibraryAdding = DejaGrooveAppleMusicLibraryAdderFactory.make()
    ) {
        self.album = album
        self.libraryAdder = libraryAdder
    }

    var body: some View {
        if album.canAddToAppleMusicLibrary {
            Button {
                Task { await addToLibrary() }
            } label: {
                if isAdding {
                    Label("Adding To Library", systemImage: "music.note.list")
                } else if hasAdded {
                    Label("Added To Apple Music Library", systemImage: "checkmark.circle")
                } else {
                    Label("Add To Apple Music Library", systemImage: "text.badge.plus")
                }
            }
            .disabled(isAdding || hasAdded)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func addToLibrary() async {
        isAdding = true
        message = nil
        do {
            try await libraryAdder.addAlbumToLibrary(album)
            hasAdded = true
            message = "Already added to Apple Music Library."
        } catch let error as AppleMusicLibraryAddError {
            message = Self.message(for: error)
        } catch {
            message = "Failed to add to Apple Music Library."
        }
        isAdding = false
    }

    private static func message(for error: AppleMusicLibraryAddError) -> String {
        switch error {
        case .missingCatalogId:
            return "Apple Music catalog ID is missing for this album."
        case .authorizationDenied:
            return "Apple Music access was not granted."
        case .authorizationRestricted:
            return "Apple Music access is restricted on this device."
        case .catalogAlbumNotFound:
            return "Album was not found in Apple Music."
        case .unavailable:
            return "Apple Music library access is not available in this build."
        }
    }
}
