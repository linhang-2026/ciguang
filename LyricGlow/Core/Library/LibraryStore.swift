import Foundation
import MediaPlayer
import SwiftData
import UIKit

@MainActor
enum LibraryStore {

        private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "aiff", "aif", "wma",
    ]

            @discardableResult
    static func importFiles(_ urls: [URL], into context: ModelContext, progress: ((Int, Int) -> Void)? = nil) async -> [TrackRecord] {
                var lyricMap: [String: URL] = [:]
        for url in urls where ["lrc", "txt"].contains(url.pathExtension.lowercased()) {
            lyricMap[url.deletingPathExtension().lastPathComponent.lowercased()] = url
        }

        var inserted: [TrackRecord] = []
        let total = urls.count
        for (index, url) in urls.enumerated() {
            if Task.isCancelled { break }
            progress?(index, total)
            let ext = url.pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { continue }
            do {
                let copy = try ImportService.copyIntoLibrary(url)
                                if let lyric = lyricMap[url.deletingPathExtension().lastPathComponent.lowercased()] {
                    let lyricDest = copy.deletingPathExtension()
                        .appendingPathExtension(lyric.pathExtension)
                    try? FileManager.default.copyItem(at: lyric, to: lyricDest)
                }

                let meta = await MetadataReader.read(from: copy)
                if let record = await insertTrack(
                    copy: copy,
                    title: meta.title ?? url.deletingPathExtension().lastPathComponent,
                    artist: meta.artist,
                    album: meta.album,
                    artworkData: meta.artworkData,
                    duration: meta.duration,
                    embeddedLyrics: meta.lyrics,
                    into: context
                ) {
                    inserted.append(record)
                }
            } catch {
                continue
            }
        }
        progress?(total, total)
        try? context.save()
        return inserted
    }

                @discardableResult
    static func importMediaItems(_ items: [MPMediaItem], into context: ModelContext, progress: ((Int, Int) -> Void)? = nil) async -> (inserted: [TrackRecord], skippedDRM: Int) {
        var inserted: [TrackRecord] = []
        var skipped = 0
        let total = items.count
        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            progress?(index, total)
            guard let assetURL = item.assetURL else {
                skipped += 1
                continue
            }
            guard let copy = try? ImportService.copyIntoLibrary(assetURL) else {
                skipped += 1
                continue
            }
                        let meta = await MetadataReader.read(from: copy)
            let artworkData = meta.artworkData
                ?? item.artwork?.image(at: CGSize(width: 600, height: 600))?.jpegData(compressionQuality: 0.9)
            if let record = await insertTrack(
                copy: copy,
                title: meta.title ?? item.title ?? copy.deletingPathExtension().lastPathComponent,
                artist: meta.artist ?? item.artist,
                album: meta.album ?? item.albumTitle,
                artworkData: artworkData,
                duration: meta.duration ?? Double(item.playbackDuration),
                embeddedLyrics: meta.lyrics,
                into: context
            ) {
                inserted.append(record)
            }
        }
        progress?(total, total)
        try? context.save()
        return (inserted, skipped)
    }

        private static func insertTrack(
        copy: URL,
        title: String,
        artist: String?,
        album: String?,
        artworkData: Data?,
        duration: Double?,
        embeddedLyrics: String?,
        into context: ModelContext
    ) async -> TrackRecord? {
        await attachLyricsIfNeeded(copy: copy, embeddedLyrics: embeddedLyrics)

        var title = title
        var artist = artist
                        let hint = lyricHeaderHint(for: copy)
        if isJunkTitle(title), let ti = hint.title { title = ti }
        if artist == nil || artist == "未知艺术家", let ar = hint.artist, !ar.isEmpty {
            artist = ar
        }
        let dominant = ThemeExtractor.dominantColor(from: artworkData)
        let record = TrackRecord(
            title: title,
            artist: artist ?? "未知艺术家",
            album: album ?? "",
            artworkData: artworkData,
            dominantColorHex: dominant?.hexString,
            fileName: copy.lastPathComponent,
            duration: duration ?? 0
        )
        context.insert(record)
        return record
    }

        static func isJunkTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespaces)
        if t.count < 2 { return true }
        if t.allSatisfy(\.isNumber) { return true }
        return t.firstMatch(
            of: /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/
        ) != nil
    }

            static func lyricHeaderHint(for audioURL: URL) -> (title: String?, artist: String?) {
        let base = audioURL.deletingPathExtension()
        for ext in ["lrc", "LRC", "txt"] {
            let url = base.appendingPathExtension(ext)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var title: String?
            var artist: String?
            for line in content.components(separatedBy: .newlines).prefix(30) {
                if title == nil, let v = LyricPatterns.meta("ti", in: line) {
                    let main = v.split(whereSeparator: { "()（）[]【】".contains($0) })
                        .first?
                        .trimmingCharacters(in: .whitespaces)
                    title = (main?.count ?? 0) >= 2 ? main : v
                }
                if artist == nil, let v = LyricPatterns.meta("ar", in: line) { artist = v }
            }
            if title != nil || artist != nil { return (title, artist) }
        }
        return (nil, nil)
    }

        static func attachLyricsIfNeeded(copy: URL, embeddedLyrics: String?) async {
        let lrcURL = copy.deletingPathExtension().appendingPathExtension("lrc")
        guard !FileManager.default.fileExists(atPath: lrcURL.path) else { return }
                if let embedded = embeddedLyrics,
           LyricMatcher.parse(embedded) != nil {
            try? embedded.write(to: lrcURL, atomically: true, encoding: .utf8)
        }
    }

            static func delete(_ record: TrackRecord, in context: ModelContext) {
        let fm = FileManager.default
        try? fm.removeItem(at: record.audioURL)
        for ext in ["lrc", "LRC", "txt"] {
            let lyric = record.audioURL.deletingPathExtension().appendingPathExtension(ext)
            try? fm.removeItem(at: lyric)
        }
        context.delete(record)
        try? context.save()
    }

                static func reconcileLibrary(in context: ModelContext) async {
        let fm = FileManager.default
        let records = (try? context.fetch(FetchDescriptor<TrackRecord>())) ?? []
        let knownFileNames = Set(records.map(\.fileName))

        for record in records where !fm.fileExists(atPath: record.audioURL.path) {
            context.delete(record)
        }

                for record in records where isJunkTitle(record.title) {
            guard fm.fileExists(atPath: record.audioURL.path),
                  let ti = lyricHeaderHint(for: record.audioURL).title,
                  !isJunkTitle(ti) else { continue }
            record.title = ti
        }

        var strangerURLs: [URL] = []
        if let files = try? fm.contentsOfDirectory(
            at: ImportService.importedDirectory,
            includingPropertiesForKeys: nil
        ) {
            strangerURLs = files.filter { file in
                audioExtensions.contains(file.pathExtension.lowercased())
                    && !knownFileNames.contains(file.lastPathComponent)
            }
        }
        for url in strangerURLs {
            let meta = await MetadataReader.read(from: url)
                        let hint = lyricHeaderHint(for: url)
            var title = meta.title ?? url.deletingPathExtension().lastPathComponent
            if isJunkTitle(title), let ti = hint.title { title = ti }
            let artist = meta.artist ?? hint.artist
            let dominant = ThemeExtractor.dominantColor(from: meta.artworkData)
            context.insert(TrackRecord(
                title: title,
                artist: artist ?? "未知艺术家",
                album: meta.album ?? "",
                artworkData: meta.artworkData,
                dominantColorHex: dominant?.hexString,
                fileName: url.lastPathComponent,
                duration: meta.duration ?? 0
            ))
        }
        try? context.save()
    }
}
