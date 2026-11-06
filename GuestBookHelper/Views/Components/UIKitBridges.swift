import SwiftUI
import UIKit

// MARK: - Search bar

struct GlobalSearchBar: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = placeholder
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.spellCheckingType = .no
        searchBar.returnKeyType = .search
        searchBar.enablesReturnKeyAutomatically = false
        searchBar.showsCancelButton = false
        searchBar.backgroundImage = UIImage()
        searchBar.tintColor = AppTheme.accentUIColor
        searchBar.isTranslucent = true
        searchBar.searchTextField.textColor = UIColor.label
        searchBar.searchTextField.backgroundColor = AppTheme.searchFillUIColor
        searchBar.searchTextField.layer.cornerRadius = 12
        searchBar.searchTextField.layer.masksToBounds = true
        searchBar.searchTextField.clearButtonMode = .whileEditing
        searchBar.searchTextField.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        searchBar.accessibilityLabel = placeholder
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        context.coordinator.text = $text
        if uiView.text != text {
            uiView.text = text
        }
        uiView.isUserInteractionEnabled = isEnabled
        uiView.alpha = isEnabled ? 1 : 0.55
        if uiView.placeholder != placeholder {
            uiView.placeholder = placeholder
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var text: Binding<String>
        init(text: Binding<String>) {
            self.text = text
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            if text.wrappedValue != searchText {
                text.wrappedValue = searchText
            }
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            text.wrappedValue = ""
        }
    }
}

// MARK: - Activity indicator

struct ActivityIndicatorView: UIViewRepresentable {
    var style: UIActivityIndicatorView.Style = .medium

    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: style)
        view.hidesWhenStopped = true
        view.startAnimating()
        return view
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {
        uiView.startAnimating()
    }
}

// MARK: - Blur

struct VisualEffectBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// MARK: - Document picker

struct SpreadsheetDocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = [
            "org.openxmlformats.spreadsheetml.sheet",
            "com.microsoft.excel.xlsx",
            "public.spreadsheet",
            "com.n1c0.guestbookhelper.ngbd",
            "ngbd"
        ]
        let picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: SpreadsheetDocumentPicker

        init(parent: SpreadsheetDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.isPresented = false
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Share sheet

struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Keyboard

enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
