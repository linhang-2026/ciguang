import MediaPlayer
import SwiftUI

struct MediaPickerView: UIViewControllerRepresentable {
        let onPick: ([MPMediaItem]) -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = true
        picker.showsCloudItems = false
        picker.delegate = context.coordinator
        picker.prompt = "选择要导入的歌"
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let onPick: ([MPMediaItem]) -> Void

        init(onPick: @escaping ([MPMediaItem]) -> Void) {
            self.onPick = onPick
        }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            onPick(mediaItemCollection.items)
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            onPick([])
        }
    }
}
