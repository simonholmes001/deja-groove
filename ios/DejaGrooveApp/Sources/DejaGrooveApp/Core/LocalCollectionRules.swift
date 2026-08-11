import Foundation

public enum LocalCollectionRules {
    public static func isDuplicate(_ lhs: Album, _ rhs: Album) -> Bool {
        if let lhsMbid = lhs.mbid, let rhsMbid = rhs.mbid, !lhsMbid.isEmpty, !rhsMbid.isEmpty, lhsMbid == rhsMbid {
            return true
        }
        if let lhsDiscogs = lhs.discogsReleaseId,
           let rhsDiscogs = rhs.discogsReleaseId,
           !lhsDiscogs.isEmpty,
           !rhsDiscogs.isEmpty,
           lhsDiscogs == rhsDiscogs {
            return true
        }
        return normalized(lhs.title) == normalized(rhs.title)
            && normalized(lhs.artist) == normalized(rhs.artist)
    }

    public static func matchesSearch(_ record: CollectionRecord, search: String?) -> Bool {
        guard let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        let query = normalized(search)
        let scalarFields: [String?] = [
            record.album.title,
            record.album.artist,
            record.notes,
            record.album.format,
            record.album.label,
            record.album.catalogNumber,
            record.album.country,
            record.album.barcode,
            record.album.discogsReleaseId,
            record.album.discogsMasterId,
            record.album.discogsUrl,
            record.album.discogsResourceUrl,
            record.album.firstReleaseDate,
            record.album.releaseDate,
            record.album.backCoverText,
            record.album.releaseNotes
        ]
        let aggregateFields: [String] = [
            record.album.genres.joined(separator: " "),
            record.album.styles.joined(separator: " "),
            record.album.companies.joined(separator: " "),
            record.album.tracklist.map(\.title).joined(separator: " "),
            record.album.identifiers.compactMap(\.value).joined(separator: " ")
        ]
        let yearFields: [String?] = [
            record.album.year.map(String.init),
            record.album.firstReleaseYear.map(String.init),
            record.album.releaseYear.map(String.init)
        ]
        let searchable = scalarFields.compactMap { $0 } + aggregateFields + yearFields.compactMap { $0 }
        return searchable.contains { normalized($0).contains(query) }
    }

    public static func matchesCollectionSearch(_ collection: CrateCollection, search: String?) -> Bool {
        guard let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return normalized(collection.name).contains(normalized(search))
    }

    public static func compareByArtistFamilyName(_ lhs: CollectionRecord, _ rhs: CollectionRecord) -> Bool {
        let lhsKey = artistSortKey(lhs.album.artist)
        let rhsKey = artistSortKey(rhs.album.artist)
        if lhsKey != rhsKey {
            return lhsKey < rhsKey
        }
        let lhsTitle = titleSortKey(lhs.album.title)
        let rhsTitle = titleSortKey(rhs.album.title)
        if lhsTitle != rhsTitle {
            return lhsTitle < rhsTitle
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    public static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    public static func cleanCollectionName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func artistSortKey(_ artist: String) -> String {
        let cleanArtist = normalized(artist)
        if cleanArtist.contains(",")
            || cleanArtist.contains("&")
            || cleanArtist.hasPrefix("the ")
            || cleanArtist.hasSuffix(" band")
            || cleanArtist.hasSuffix(" quartet")
            || cleanArtist.hasSuffix(" quintet")
            || cleanArtist.hasSuffix(" trio") {
            return cleanArtist
        }
        let parts = cleanArtist.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return cleanArtist }
        return "\(parts.last!) \(parts.dropLast().joined(separator: " "))"
    }

    private static func titleSortKey(_ title: String) -> String {
        let cleanTitle = normalized(title)
        for article in ["the ", "a ", "an "] where cleanTitle.hasPrefix(article) {
            return String(cleanTitle.dropFirst(article.count))
        }
        return cleanTitle
    }
}
