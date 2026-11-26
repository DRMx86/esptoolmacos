import SwiftUI
import AppKit

/// NSTextView-backed terminal output. Much faster than a SwiftUI Text for streaming logs.
struct TerminalView: NSViewRepresentable {
    @ObservedObject var monitor: SerialMonitor
    let palette: Palette
    let autoscroll: Bool

    private static let maxChars = 300_000
    private static let keepChars = 200_000

    final class Coordinator {
        var clearToken = -1
        var themeID = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.borderType = .noBorder

        if let tv = scroll.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.isRichText = false
            tv.allowsUndo = false
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.textContainerInset = NSSize(width: 10, height: 10)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView,
              let storage = tv.textStorage else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let fg = NSColor(palette.terminalText)
        let bg = NSColor(palette.terminalBackground)
        let coord = context.coordinator

        scroll.backgroundColor = bg
        tv.backgroundColor = bg
        tv.insertionPointColor = fg
        tv.typingAttributes = [.font: font, .foregroundColor: fg]

        if coord.themeID != palette.id {
            coord.themeID = palette.id
            if storage.length > 0 {
                storage.addAttribute(.foregroundColor, value: fg, range: NSRange(location: 0, length: storage.length))
            }
        }

        if coord.clearToken != monitor.clearToken {
            coord.clearToken = monitor.clearToken
            storage.setAttributedString(NSAttributedString(string: ""))
        }

        let incoming = monitor.takePending()
        guard !incoming.isEmpty else { return }

        storage.append(NSAttributedString(string: incoming, attributes: [.font: font, .foregroundColor: fg]))
        if storage.length > Self.maxChars {
            storage.deleteCharacters(in: NSRange(location: 0, length: storage.length - Self.keepChars))
        }
        if autoscroll {
            tv.scrollToEndOfDocument(nil)
        }
    }
}
