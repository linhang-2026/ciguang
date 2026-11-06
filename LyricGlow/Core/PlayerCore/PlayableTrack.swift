import Foundation

struct PlayableTrack: Identifiable, Hashable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var artworkData: Data?
    var audioURL: URL
        var duration: Double?

    init(id: UUID = UUID(),
         title: String,
         artist: String = "未知艺术家",
         album: String = "",
         artworkData: Data? = nil,
         audioURL: URL,
         duration: Double? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.audioURL = audioURL
        self.duration = duration
    }
}
