import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [TrackRecord]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("使用帮助", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("教程")
                } footer: {
                    Text("导入音乐、配歌词、播放与歌词页的完整用法都在这里")
                }

                Section {
                    LabeledContent("版本") {
                        Text(versionString)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("歌曲数量") {
                        Text("\(records.count) 首")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("关于")
                }

                Section {
                    Label(
                        "词光是纯本地播放器：不联网、不注册、不收集数据，歌曲与歌词只存在这台手机上。",
                        systemImage: "lock.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } footer: {
                    Text(" iCloud 云盘导入走系统「文件」能力，仅在你主动选择时使用。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                helpSection(
                    icon: "waveform",
                    title: "词光是什么",
                    paragraphs: TutorialText.welcome,
                    highlights: TutorialText.welcomeHighlights
                )
                helpSection(
                    icon: "square.and.arrow.down.on.square",
                    title: "导入音乐",
                    paragraphs: TutorialText.importMusic,
                    highlights: TutorialText.importMusicHighlights
                )
                helpSection(
                    icon: "text.quote",
                    title: "配歌词（三种方式）",
                    paragraphs: TutorialText.lyrics,
                    highlights: TutorialText.lyricsHighlights
                )
                helpSection(
                    icon: "play.circle",
                    title: "播放与歌词页",
                    paragraphs: TutorialText.playback,
                    highlights: TutorialText.playbackHighlights
                )
                helpSection(
                    icon: "questionmark.circle",
                    title: "常见问题",
                    paragraphs: [
                        "歌词和歌对不上？歌词页顶部菜单里用「歌词校准」微调，每次 0.1 秒或 1 秒。",
                        "导入 Apple Music 的歌没反应？在线流媒体有版权保护，先在系统音乐 App 里下载到本地再导入。",
                        "歌词文件不认识？确认内容带时间轴（如 [00:12.34]），纯文字歌词没法逐字跟唱。",
                        "想删歌？卡片长按（或右键）菜单里有删除和编辑。",
                    ]
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .navigationTitle("使用帮助")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private func helpSection(icon: String, title: String, paragraphs: [String], highlights: [String]? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(paragraphs, id: \.self) { text in
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineSpacing(5)
                }
                if let highlights {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(highlights, id: \.self) { text in
                            HStack(alignment: .top, spacing: 8) {
                                Text("·")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.45))
                                Text(text)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineSpacing(4)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
