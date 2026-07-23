import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct VideoCameraPickerView: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.mediaTypes = [UTType.movie.identifier]
        controller.cameraCaptureMode = .video
        controller.videoQuality = .typeHigh
        controller.videoMaximumDuration = 180
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onPicked: (URL) -> Void
        private let onCancel: () -> Void

        init(onPicked: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let url = info[.mediaURL] as? URL else {
                onCancel()
                return
            }
            onPicked(url)
        }
    }
}

struct ImportedEvidenceVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let fileExtension = received.file.pathExtension.isEmpty
                ? "mov"
                : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString).\(fileExtension)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedEvidenceVideo(url: destination)
        }
    }
}
