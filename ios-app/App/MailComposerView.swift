@preconcurrency import MessageUI
import SwiftUI

struct MailDraft: Identifiable {
    let id = UUID()
    let recipients: [String]
    let subject: String
    let body: String
    let attachmentURL: URL
}

struct MailComposerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let draft: MailDraft

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(draft.recipients)
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)

        if let data = try? Data(contentsOf: draft.attachmentURL) {
            controller.addAttachmentData(
                data,
                mimeType: "application/pdf",
                fileName: draft.attachmentURL.lastPathComponent
            )
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            dismiss()
        }
    }
}

