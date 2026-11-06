import PhotosUI
import SwiftData
import SwiftUI

struct TrackEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let record: TrackRecord
    let onSaved: () -> Void

    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var artworkData: Data?
    @State private var showPhotoPicker = false
    @State private var showLyricImporter = false
        @State private var lyricNotice: String?
        @State private var hasLyrics: Bool

    init(record: TrackRecord, onSaved: @escaping () -> Void = {}) {
        self.record = record
        self.onSaved = onSaved
        _title = State(initialValue: record.title)
        _artist = State(initialValue: record.artist == "未知艺术家" ? "" : record.artist)
        _album = State(initialValue: record.album)
        _artworkData = State(initialValue: record.artworkData)
        _hasLyrics = State(initialValue: LyricMatcher.findLocalLyrics(for: record.audioURL) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("封面") {
                    HStack(spacing: 16) {
                        ArtworkThumbnail(data: artworkData, size: 72)
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                showPhotoPicker = true
                            } label: {
                                Text(artworkData == nil ? "选择图片" : "更换图片")
                                    .font(.subheadline.weight(.medium))
                            }
                            if artworkData != nil {
                                Button(role: .destructive) {
                                    artworkData = nil
                                } label: {
                                    Text("移除封面")
                                        .font(.subheadline)
                                }
                            }
                        }
                        Spacer()
                    }
                }
                Section("歌曲信息") {
                    LabeledContent("标题") {
                        TextField("歌名", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("歌手") {
                        TextField("歌手名", text: $artist)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("专辑") {
                        TextField("专辑名", text: $album)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Label(
                        title.isEmpty ? "填好标题再保存" : "改完名字点保存即可",
                        systemImage: "text.bubble"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Section("歌词") {
                    LabeledContent("状态") {
                        Text(hasLyrics ? "已有歌词" : "暂无歌词")
                            .foregroundStyle(hasLyrics ? .primary : .secondary)
                    }
                    Button {
                        showLyricImporter = true
                    } label: {
                        Label("导入歌词文件", systemImage: "folder")
                    }
                    Button {
                        pasteLyrics()
                    } label: {
                        Label("粘贴剪贴板歌词", systemImage: "doc.on.clipboard")
                    }
                    if hasLyrics {
                        Button(role: .destructive) {
                            LyricMatcher.removeLyrics(for: record.audioURL)
                            hasLyrics = false
                        } label: {
                            Label("移除歌词", systemImage: "trash")
                        }
                    }
                    Text("支持 LRC / QRC / TTML 等常见歌词格式，带时间轴才能逐字跟唱")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("编辑歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker { image in
                    showPhotoPicker = false
                    if let image {
                        artworkData = image.jpegData(compressionQuality: 0.9)
                    }
                }
            }
            .fileImporter(
                isPresented: $showLyricImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    importLyrics(from: url)
                }
            }
            .alert("歌词", isPresented: Binding(
                get: { lyricNotice != nil },
                set: { if !$0 { lyricNotice = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(lyricNotice ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let newTitle = title.trimmingCharacters(in: .whitespaces)
        let newArtist = artist.trimmingCharacters(in: .whitespaces)
        let newAlbum = album.trimmingCharacters(in: .whitespaces)

        record.title = newTitle
        record.artist = newArtist.isEmpty ? "未知艺术家" : newArtist
        record.album = newAlbum
        record.artworkData = artworkData
        record.dominantColorHex = ThemeExtractor.dominantColor(from: artworkData)?.hexString
        try? modelContext.save()
                onSaved()
        dismiss()
    }

        private func importLyrics(from url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              LyricMatcher.parse(content) != nil else {
            lyricNotice = "这个文件不像带时间轴的歌词（支持 LRC、QRC、TTML 等格式）"
            return
        }
        LyricMatcher.saveLyrics(content, for: record.audioURL, overwrite: true)
        hasLyrics = true
    }

        private func pasteLyrics() {
        guard let content = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            lyricNotice = "剪贴板里没有歌词文本，先复制一份再回来粘贴"
            return
        }
        guard LyricMatcher.parse(content) != nil else {
            lyricNotice = "剪贴板里的内容不像带时间轴的歌词（支持 LRC、QRC、TTML 等格式）"
            return
        }
        LyricMatcher.saveLyrics(content, for: record.audioURL, overwrite: true)
        hasLyrics = true
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                onPick(nil)
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    self.onPick(object as? UIImage)
                }
            }
        }
    }
}
