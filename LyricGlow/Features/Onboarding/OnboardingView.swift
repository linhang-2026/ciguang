import SwiftUI

struct OnboardingView: View {
        static let hasSeenKey = "hasSeenOnboarding"

    let onFinished: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                tutorialPage(
                    icon: "waveform",
                    title: "欢迎来到词光",
                    paragraphs: TutorialText.welcome,
                    highlights: TutorialText.welcomeHighlights
                ).tag(0)
                tutorialPage(
                    icon: "square.and.arrow.down.on.square",
                    title: "把音乐放进来",
                    paragraphs: TutorialText.importMusic,
                    highlights: TutorialText.importMusicHighlights
                ).tag(1)
                tutorialPage(
                    icon: "text.quote",
                    title: "给歌配上歌词",
                    paragraphs: TutorialText.lyrics,
                    highlights: TutorialText.lyricsHighlights
                ).tag(2)
                tutorialPage(
                    icon: "play.circle",
                    title: "播放与歌词页",
                    paragraphs: TutorialText.playback,
                    highlights: TutorialText.playbackHighlights
                ).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 3 {
                    withAnimation { page += 1 }
                } else {
                    onFinished()
                }
            } label: {
                Text(page < 3 ? "下一页" : "开始使用")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(.white, in: Capsule())
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)

            if page == 3 {
                Button("跳过，直接用") { onFinished() }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .background(Color.black.ignoresSafeArea())
    }

    private func tutorialPage(icon: String, title: String, paragraphs: [String], highlights: [String]? = nil) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 72)
                Text(title)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(paragraphs, id: \.self) { text in
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineSpacing(5)
                    }
                    if let highlights {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(highlights, id: \.self) { text in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.5))
                                        .padding(.top, 2)
                                    Text(text)
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.6))
                                        .lineSpacing(4)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 36)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

enum TutorialText {
    static let welcome = [
        "词光是一款纯本地音乐播放器：歌、歌词、封面都只存在这台手机上。",
        "它不联网、不注册、不收集任何数据，也没有开屏广告。",
    ]
    static let welcomeHighlights: [String] = [
        "所有文件保存在 App 沙盒里，卸载即彻底清除",
        "支持 FLAC、MP3、AAC、WAV 等常见格式",
    ]

    static let importMusic = [
        "点首页右上角的 +，两种方式任选：",
        "「导入音频文件」从文件 App（含 iCloud 云盘）选歌；「从 Apple 音乐曲库导入」选已下载到本地的歌。",
    ]
    static let importMusicHighlights: [String] = [
        "FLAC 无损、MP3、AAC、WAV、OGG 都能播",
        "Apple Music 在线流媒体有版权保护导不出来，先在系统音乐里下载到本地再选",
        "微信/QQ 里收到的音频也可以用「其他应用打开 → 词光」直接导入",
    ]

    static let lyrics = [
        "词光不联网，歌词要自己配上，三种方式：",
    ]
    static let lyricsHighlights: [String] = [
        "同名自动配：导入时把歌词文件和歌放一起、文件名相同（如 宿敌.flac + 宿敌.lrc），会自动关联",
        "手动导入：歌词页没有歌词时点「导入歌词文件」，或在歌曲编辑页（卡片长按 → 编辑）里导入",
        "剪贴板粘贴：复制歌词全文，在编辑页点「粘贴剪贴板歌词」",
        "支持 LRC、QRC、YRC、TTML 等格式，逐字时间轴的歌效果最好",
    ]

    static let playback = [
        "点封面卡片即播放，底部迷你条上滑进入播放页。",
        "播放页往下拉是沉浸式歌词：整首歌像一份报纸铺在空间里，相机跟着唱到的位置走。",
        "歌词页顶部菜单可以换风格（烬语 / 萤川 / 镜渊）、换背景、校准歌词快慢，还能全屏沉浸。",
    ]
    static let playbackHighlights: [String] = [
        "点任意一句歌词可以直接跳到那一句",
        "歌词快慢不对：菜单里「歌词校准」每次调 0.1 秒或 1 秒",
        "「设置 → 使用帮助」随时回看这份教程",
    ]
}
