import Foundation
import SwiftData

@Model
final class TrackRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var album: String
        @Attribute(.externalStorage) var artworkData: Data?
        var dominantColorHex: String?
        var fileName: String
        var duration: Double
    var importedAt: Date
        var metadataFilled: Bool

    init(id: UUID = UUID(),
         title: String,
         artist: String,
         album: String = "",
         artworkData: Data? = nil,
         dominantColorHex: String? = nil,
         fileName: String,
         duration: Double,
         importedAt: Date = .now) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.dominantColorHex = dominantColorHex
        self.fileName = fileName
        self.duration = duration
        self.importedAt = importedAt
        self.metadataFilled = false
    }
}

extension TrackRecord {
        var audioURL: URL {
        ImportService.importedDirectory.appendingPathComponent(fileName)
    }

        var playable: PlayableTrack {
        PlayableTrack(
            id: id,
            title: title,
            artist: artist,
            album: album,
            artworkData: artworkData,
            audioURL: audioURL,
            duration: duration
        )
    }
}
