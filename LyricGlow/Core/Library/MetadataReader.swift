import AVFoundation
import Foundation

struct TrackMetadata: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var artworkData: Data?
    var duration: Double?
        var lyrics: String?
}

enum MetadataReader {
    static func read(from url: URL) async -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        var result = TrackMetadata()

        guard let metadata = try? await asset.load(.commonMetadata),
              let duration = try? await asset.load(.duration)
        else {
            return result
        }
        if duration.seconds.isFinite {
            result.duration = duration.seconds
        }

        for item in metadata {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle:
                result.title = try? await item.load(.value) as? String
            case .commonKeyArtist:
                result.artist = try? await item.load(.value) as? String
            case .commonKeyAlbumName:
                result.album = try? await item.load(.value) as? String
            case .commonKeyArtwork:
                result.artworkData = try? await item.load(.value) as? Data
            default:
                break
            }
        }

                        if result.title == nil || result.artist == nil || result.album == nil,
           let all = try? await asset.load(.metadata) {
            for item in all {
                guard item.keySpace?.rawValue == "vorb",
                      let key = (item.key as? String)?.lowercased() else { continue }
                let value = try? await item.load(.value) as? String
                guard let value, !value.isEmpty else { continue }
                switch key {
                case "title" where result.title == nil: result.title = value
                case "artist" where result.artist == nil: result.artist = value
                case "album" where result.album == nil: result.album = value
                default: break
                }
            }
        }

        result.lyrics = await readEmbeddedLyrics(asset: asset)
        if url.pathExtension.lowercased() == "flac" {
            if result.lyrics == nil {
                result.lyrics = readFlacVorbisField(url: url, keys: ["LYRICS", "UNSYNCEDLYRICS", "SYNCEDLYRICS", "LYRIC"])
            }
                        if result.artworkData == nil {
                result.artworkData = readFlacArtwork(url: url)
            }
        }
        return result
    }

        private static func readEmbeddedLyrics(asset: AVAsset) async -> String? {
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        for item in metadata {
            if let identifier = item.identifier {
                if identifier == .id3MetadataUnsynchronizedLyric
                    || identifier == .iTunesMetadataLyrics {
                    if let text = try? await item.load(.value) as? String, !text.isEmpty {
                        return text
                    }
                }
                continue
            }
            if let key = item.key as? String, let space = item.keySpace,
               space == .isoUserData, key.lowercased().contains("lyr") {
                if let text = try? await item.load(.value) as? String, !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

            private static func scanFlacBlocks(
        url: URL, maxBlock: Int = 8 * 1024 * 1024, visitor: (Int, Data) -> Bool
    ) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 4), header.count == 4,
              header == Data("fLaC".utf8) else { return }

        while true {
            guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return }
            let type = Int(head[0]) & 0x7F
            let isLast = (Int(head[0]) & 0x80) != 0
            let length = (Int(head[1]) << 16) | (Int(head[2]) << 8) | Int(head[3])
            guard length >= 0, length < maxBlock else { return }

            if length > 0 {
                if let block = try? handle.read(upToCount: length), block.count == length {
                    if visitor(type, block) { return }
                } else {
                    return
                }
            }
            if isLast { return }
        }
    }

        private static func readFlacVorbisField(url: URL, keys: [String]) -> String? {
        var result: String?
        scanFlacBlocks(url: url) { type, block in
            guard type == 4 else { return false }
            result = parseVorbisComment(block, keys: keys)
            return result != nil
        }
        return result
    }

        private static func readFlacArtwork(url: URL) -> Data? {
        var fromBlock: Data?
        var base64Comment: String?
        scanFlacBlocks(url: url) { type, block in
            if type == 6, fromBlock == nil {
                fromBlock = parseFlacPictureBlock(block)
            } else if type == 4, base64Comment == nil {
                base64Comment = parseVorbisComment(block, keys: ["METADATA_BLOCK_PICTURE"])
            }
            return fromBlock != nil && base64Comment != nil
        }
        if let fromBlock { return fromBlock }
        guard let base64Comment, let raw = Data(base64Encoded: base64Comment) else { return nil }
        return parseFlacPictureBlock(raw)
    }

            private static func parseFlacPictureBlock(_ data: Data) -> Data? {
        var offset = 4
        func be32() -> Int? {
            guard offset + 4 <= data.count else { return nil }
            let v = Int(data[data.startIndex + offset]) << 24
                | Int(data[data.startIndex + offset + 1]) << 16
                | Int(data[data.startIndex + offset + 2]) << 8
                | Int(data[data.startIndex + offset + 3])
            offset += 4
            return v >= 0 ? v : nil
        }
        guard let mimeLength = be32(), offset + mimeLength <= data.count else { return nil }
        offset += mimeLength
        guard let descLength = be32(), offset + descLength <= data.count else { return nil }
        offset += descLength
        guard be32() != nil, be32() != nil, be32() != nil, be32() != nil else { return nil }
        guard let dataLength = be32(), dataLength > 0, dataLength < 16 * 1024 * 1024,
              offset + dataLength <= data.count else { return nil }
        return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + dataLength))
    }

        private static func parseVorbisComment(_ data: Data, keys: [String]) -> String? {
        let keySet = Set(keys.map { $0.uppercased() })
        var offset = 0
        func le32() -> Int? {
            guard offset + 4 <= data.count else { return nil }
            let v = Int(data[data.startIndex + offset])
                | Int(data[data.startIndex + offset + 1]) << 8
                | Int(data[data.startIndex + offset + 2]) << 16
                | Int(data[data.startIndex + offset + 3]) << 24
            offset += 4
            return v >= 0 ? v : nil
        }

        guard let vendorLength = le32(), offset + vendorLength <= data.count else { return nil }
        offset += vendorLength
        guard let count = le32() else { return nil }
        for _ in 0..<min(count, 4096) {
            guard let fieldLength = le32() else { return nil }
            guard fieldLength >= 0, fieldLength < 4 * 1024 * 1024,
                  offset + fieldLength <= data.count else { return nil }
            guard let str = String(
                data: data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + fieldLength)),
                encoding: .utf8
            ) else { return nil }
            offset += fieldLength
            guard let eq = str.firstIndex(of: "=") else { continue }
            let key = String(str[..<eq]).uppercased()
            let value = String(str[str.index(after: eq)...])
            if keySet.contains(key), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
