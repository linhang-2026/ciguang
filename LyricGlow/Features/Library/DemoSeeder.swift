#if DEBUG
import AVFoundation
import SwiftUI
import SwiftData

enum DemoSeeder {
    private static let seededFlag = "demoSeeded"

        private struct DemoSong {
        let title: String
        let artist: String
        let album: String
        let hueA: CGFloat
        let hueB: CGFloat
        let seconds: Double
        let lyrics: String
    }

    static func seedIfNeeded(in context: ModelContext) async {
        guard !UserDefaults.standard.bool(forKey: seededFlag) else { return }
        UserDefaults.standard.set(true, forKey: seededFlag)
        try? ImportService.ensureDirectory()
        let songs = demoSongs()
        for song in songs {
            let fileBase = "demo-\(song.title)"
            let audioURL = ImportService.importedDirectory
                .appendingPathComponent(fileBase)
                .appendingPathExtension("wav")
            guard !FileManager.default.fileExists(atPath: audioURL.path) else { continue }
            writeToneWav(to: audioURL, seconds: song.seconds)
                        try? song.lyrics.write(
                to: ImportService.importedDirectory
                    .appendingPathComponent(fileBase)
                    .appendingPathExtension("lrc"),
                atomically: true, encoding: .utf8
            )
            let artwork = coverArt(hueA: song.hueA, hueB: song.hueB)
            let dominant = ThemeExtractor.dominantColor(from: artwork)
            context.insert(TrackRecord(
                title: song.title,
                artist: song.artist,
                album: song.album,
                artworkData: artwork,
                dominantColorHex: dominant?.hexString,
                fileName: audioURL.lastPathComponent,
                duration: song.seconds
            ))
        }
        try? context.save()
    }

    private static func writeToneWav(to url: URL, seconds: Double) {
        let sampleRate = 44100.0
        let frames = AVAudioFrameCount(sampleRate * seconds)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        ), let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        let fade = 2.0 * sampleRate
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            var sample = sin(2 * .pi * 220.0 * t) * 0.14 + sin(2 * .pi * 329.63 * t) * 0.10
                        sample *= 0.85 + 0.15 * sin(2 * .pi * 0.2 * t)
            let tail = Double(i) / fade
            let head = Double(Int(frames) - i) / fade
            data[i] = Float(sample * min(1, min(tail, head)))
        }
        try? file.write(from: buffer)
    }

    private static func coverArt(hueA: CGFloat, hueB: CGFloat) -> Data {
        let size = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { uiCtx in
            let ctx = uiCtx.cgContext
            let rect = CGRect(origin: .zero, size: size)
            ctx.saveGState()
            ctx.clip(to: [rect])
            CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(hue: hueA, saturation: 0.72, brightness: 0.30, alpha: 1).cgColor,
                    UIColor(hue: hueB, saturation: 0.65, brightness: 0.55, alpha: 1).cgColor
                ] as CFArray, locations: [0, 1]
            )!.withDrawing(in: ctx, startPoint: .zero, endPoint: CGPoint(x: 0, y: 1))
            ctx.restoreGState()
            ctx.setBlendMode(.plusLighter)
            for blob in [
                (x: 680.0, y: 300.0, r: 330.0, hue: hueB),
                (x: 320.0, y: 760.0, r: 400.0, hue: hueA)
            ] {
                ctx.setFillColor(
                    UIColor(hue: blob.hue, saturation: 0.5, brightness: 0.9, alpha: 0.35).cgColor
                )
                ctx.fillEllipse(in: CGRect(
                    x: blob.x - blob.r / 2, y: blob.y - blob.r / 2,
                    width: blob.r, height: blob.r
                ))
            }
        }
        return image.pngData() ?? Data()
    }

    private static func demoSongs() -> [DemoSong] {
        [
            DemoSong(
                title: "词光", artist: "林航云", album: "词光",
                hueA: 0.62, hueB: 0.86, seconds: 96,
                lyrics: """
                [ti:词光]
                [ar:林航云]
                [00:04.00]<00:04.00>夜<00:04.42>里<00:04.86>的<00:05.30>字<00:05.90>会<00:06.40>发<00:07.00>光
                [00:10.00]<00:10.00>一<00:10.40>句<00:10.80>一<00:11.30>句<00:11.80>漫<00:12.30>过<00:12.90>耳<00:13.50>畔
                [00:17.00]<00:17.00>像<00:17.45>谁<00:17.90>把<00:18.45>心<00:19.00>事<00:19.60>折<00:20.10>成<00:20.70>了<00:21.30>纸<00:21.90>船
                [00:25.00]<00:25.00>顺<00:25.50>着<00:26.00>旋<00:26.50>律<00:27.00>漂<00:27.60>向<00:28.20>远<00:28.80>方
                [00:33.00]<00:33.00>我<00:33.42>把<00:33.84>音<00:34.26>量<00:34.80>调<00:35.30>得<00:35.80>很<00:36.30>轻
                [00:39.00]<00:39.00>让<00:39.45>每<00:39.90>个<00:40.40>字<00:40.95>都<00:41.50>走<00:42.05>得<00:42.60>很<00:43.15>慢
                [00:47.00]<00:47.00>时<00:47.42>间<00:47.84>在<00:48.30>这<00:48.80>里<00:49.30>放<00:49.80>下<00:50.40>了<00:50.95>脚<00:51.50>步
                [00:55.00]<00:55.00>只<00:55.45>陪<00:55.95>我<00:56.50>把<00:57.05>这<00:57.60>首<00:58.15>歌<00:58.70>听<00:59.30>完
                [01:04.00]<01:04.00>灯<01:04.42>光<01:04.86>落<01:05.30>在<01:05.80>歌<01:06.35>词<01:06.90>的<01:07.40>缝<01:07.95>隙<01:08.50>里
                [01:12.00]<01:12.00>夜<01:12.42>就<01:12.84>变<01:13.30>得<01:13.80>温<01:14.30>柔<01:14.90>而<01:15.50>具<01:16.00>体
                [01:20.00]<01:20.00>词<01:20.45>光<01:20.95>落<01:21.50>满<01:22.10>了<01:22.70>整<01:23.30>个<01:23.90>房<01:24.50>间
                """
            ),
            DemoSong(
                title: "夜航星", artist: "苏和野", album: "词光",
                hueA: 0.58, hueB: 0.50, seconds: 64,
                lyrics: """
                [ti:夜航星]
                [ar:苏和野]
                [00:04.00]<00:04.00>把<00:04.45>白<00:04.90>天<00:05.40>折<00:05.95>好<00:06.50>收<00:07.05>进<00:07.60>口<00:08.15>袋
                [00:12.00]<00:12.00>今<00:12.45>晚<00:12.90>只<00:13.40>剩<00:13.95>星<00:14.50>星<00:15.10>和<00:15.70>耳<00:16.30>机
                [00:20.00]<00:20.00>导<00:20.42>航<00:20.90>没<00:21.40>有<00:21.95>目<00:22.50>的<00:23.05>地<00:23.60>也<00:24.20>没<00:24.80>关<00:25.40>系
                [00:29.00]<00:29.00>音<00:29.45>乐<00:29.95>开<00:30.50>到<00:31.05>哪<00:31.65>里<00:32.20>就<00:32.80>飞<00:33.50>到<00:34.20>哪<00:34.90>里
                [00:40.00]<00:40.00>夜<00:40.45>航<00:40.95>的<00:41.45>人<00:42.00>不<00:42.55>需<00:43.10>要<00:43.70>睡<00:44.30>意
                [00:48.00]<00:48.00>只<00:48.50>要<00:49.05>一<00:49.60>首<00:50.20>接<00:50.80>一<00:51.40>首<00:52.00>的<00:52.60>旋<00:53.20>律
                """
            ),
            DemoSong(
                title: "雾中灯", artist: "苏和野", album: "词光",
                hueA: 0.07, hueB: 0.78, seconds: 64,
                lyrics: """
                [ti:雾中灯]
                [ar:苏和野]
                [00:04.00]<00:04.00>雾<00:04.45>从<00:04.90>窗<00:05.40>外<00:05.95>慢<00:06.50>慢<00:07.10>涌<00:07.70>进<00:08.30>来
                [00:12.00]<00:12.00>灯<00:12.45>把<00:12.90>它<00:13.40>染<00:13.95>成<00:14.50>温<00:15.10>柔<00:15.70>的<00:16.30>海
                [00:20.00]<00:20.00>歌<00:20.42>词<00:20.86>一<00:21.35>个<00:21.90>字<00:22.45>一<00:23.00>个<00:23.55>字<00:24.10>亮<00:24.75>起<00:25.40>来
                [00:29.00]<00:29.00>像<00:29.45>雾<00:29.95>里<00:30.50>有<00:31.05>人<00:31.65>提<00:32.25>着<00:32.85>灯<00:33.50>走<00:34.20>过<00:34.90>来
                [00:40.00]<00:40.00>这<00:40.42>一<00:40.90>路<00:41.40>的<00:41.95>模<00:42.50>糊<00:43.05>和<00:43.65>清<00:44.25>醒
                [00:48.00]<00:48.00>都<00:48.45>交<00:48.95>给<00:49.45>耳<00:50.00>朵<00:50.55>去<00:51.10>裁<00:51.70>定
                """
            ),
            DemoSong(
                title: "潮汐备忘录", artist: "白帆纪", album: "词光",
                hueA: 0.45, hueB: 0.62, seconds: 64,
                lyrics: """
                [ti:潮汐备忘录]
                [ar:白帆纪]
                [00:04.00]<00:04.00>浪<00:04.45>把<00:04.90>昨<00:05.40>天<00:05.95>写<00:06.50>成<00:07.10>了<00:07.70>备<00:08.30>忘<00:08.90>录
                [00:12.00]<00:12.00>退<00:12.45>潮<00:12.90>的<00:13.40>时<00:13.95>候<00:14.50>再<00:15.10>一<00:15.70>页<00:16.30>页<00:16.90>读
                [00:20.00]<00:20.00>耳<00:20.42>机<00:20.86>里<00:21.35>的<00:21.90>风<00:22.45>慢<00:23.00>慢<00:23.55>变<00:24.10>成<00:24.75>了<00:25.40>海<00:26.00>风
                [00:29.00]<00:29.00>把<00:29.45>所<00:29.95>有<00:30.50>心<00:31.05>事<00:31.65>都<00:32.25>吹<00:32.85>得<00:33.50>很<00:34.20>轻<00:34.90>松
                [00:40.00]<00:40.00>记<00:40.42>住<00:40.86>的<00:41.40>就<00:41.90>留<00:42.40>下<00:42.95>来
                [00:48.00]<00:48.00>忘<00:48.45>记<00:48.95>的<00:49.45>就<00:50.00>随<00:50.55>它<00:51.10>去<00:51.70>吧
                """
            )
        ]
    }
}

private extension CGGradient {
    func withDrawing(in ctx: CGContext, startPoint: CGPoint, endPoint: CGPoint) {
        ctx.drawLinearGradient(
            self, start: startPoint, end: endPoint,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
}
#endif
