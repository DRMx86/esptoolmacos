import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FlashView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var scanner: PortScanner
    @EnvironmentObject var flasher: Flasher
    @EnvironmentObject var monitor: SerialMonitor

    @State private var dropTargeted = false
    @State private var confirmErase = false

    private var running: Bool { flasher.isRunning }
    private var hasPort: Bool { scanner.selected != nil }
    private var hasTool: Bool { flasher.esptoolPath != nil }

    var body: some View {
        let p = theme.palette
        VStack(spacing: 16) {
            if !hasTool && !flasher.isDetecting {
                missingToolCard(p)
            }
            targetCard(p)
            firmwareCard(p)
            actionBar(p)
            if flasher.showsProgress && (running || flasher.state == .success) {
                progressRow(p)
            }
            logPanel(p)
        }
        .padding(24)
        .alert("Erase entire flash?", isPresented: $confirmErase) {
            Button("Erase", role: .destructive) {
                perform { port, done in flasher.eraseFlash(port: port, onFinish: done) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All data on the board's flash, including firmware and stored settings, will be wiped.")
        }
    }

    // MARK: Cards

    private func targetCard(_ p: Palette) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Port", p: p)
                Text(scanner.selectedPort?.path ?? "None selected")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(hasPort ? p.text : p.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Flash baud", p: p)
                ThemedMenu(
                    p: p,
                    options: Flasher.baudRates,
                    selection: $flasher.flashBaud,
                    label: { String($0) }
                )
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Erase first", p: p)
                Toggle("", isOn: $flasher.eraseAll)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Erase the entire flash before writing (--erase-all)")
            }
        }
        .card(p)
        .disabled(running)
    }

    private func firmwareCard(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Firmware", p: p)
                Spacer()
                Button {
                    pickFiles()
                } label: {
                    Label("Add file", systemImage: "plus")
                }
                .buttonStyle(ThemedButtonStyle(p: p, kind: .secondary))
                .disabled(running)
            }

            if flasher.files.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 20))
                    Text("Drop .bin files here")
                        .font(.system(size: 13, weight: .medium, design: p.fontDesign))
                    Text("Merged image → 0x0 · app only → 0x10000")
                        .font(.system(size: 11, design: p.fontDesign))
                }
                .foregroundColor(p.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($flasher.files) { $file in
                            fileRow($file, p)
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
        }
        .card(p)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundColor(dropTargeted ? p.accent : Color.clear)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async { flasher.addFile(url) }
                    }
                }
            }
            return true
        }
    }

    private func fileRow(_ file: Binding<FlashFile>, _ p: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .foregroundColor(p.accent)
            TextField("0x10000", text: file.address)
                .themedField(p)
                .frame(width: 110)
                .disabled(running)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.wrappedValue.url.lastPathComponent)
                    .font(.system(size: 13, design: p.fontDesign))
                    .foregroundColor(p.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileSize(file.wrappedValue.url))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(p.secondaryText)
            }
            Spacer(minLength: 0)
            Button {
                let id = file.wrappedValue.id
                flasher.files.removeAll { $0.id == id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(p.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(running)
        }
    }

    private func actionBar(_ p: Palette) -> some View {
        HStack(spacing: 10) {
            Button {
                perform { port, done in flasher.flash(port: port, onFinish: done) }
            } label: {
                Label("Flash", systemImage: "bolt.fill")
            }
            .buttonStyle(ThemedButtonStyle(p: p, kind: .primary))
            .disabled(!hasPort || !hasTool || running || flasher.files.isEmpty)

            Button {
                perform { port, done in flasher.chipInfo(port: port, onFinish: done) }
            } label: {
                Label("Chip info", systemImage: "info.circle")
            }
            .buttonStyle(ThemedButtonStyle(p: p, kind: .secondary))
            .disabled(!hasPort || !hasTool || running)

            Button {
                confirmErase = true
            } label: {
                Label("Erase", systemImage: "trash")
            }
            .buttonStyle(ThemedButtonStyle(p: p, kind: .danger))
            .disabled(!hasPort || !hasTool || running)

            if running {
                Button {
                    flasher.cancel()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(ThemedButtonStyle(p: p, kind: .danger))
            }

            Spacer()

            toolStatus(p)
        }
    }

    private func toolStatus(_ p: Palette) -> some View {
        HStack(spacing: 8) {
            if flasher.isDetecting {
                Text("Looking for esptool…")
                    .foregroundColor(p.secondaryText)
            } else if let path = flasher.esptoolPath {
                StatusDot(color: p.success)
                Text("esptool \(flasher.esptoolVersion)")
                    .foregroundColor(p.secondaryText)
                    .help(path)
                Button("Change") { locateTool() }
                    .buttonStyle(.plain)
                    .foregroundColor(p.accent)
            } else {
                StatusDot(color: p.danger)
                Text("esptool not found")
                    .foregroundColor(p.danger)
            }
        }
        .font(.system(size: 11, design: p.fontDesign))
    }

    private func missingToolCard(_ p: Palette) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(p.danger)
            VStack(alignment: .leading, spacing: 3) {
                Text("esptool not found")
                    .font(.system(size: 13, weight: .semibold, design: p.fontDesign))
                    .foregroundColor(p.text)
                Text("Install it with `brew install esptool` or `pipx install esptool`, then re-check — or point the app at your copy.")
                    .font(.system(size: 11, design: p.fontDesign))
                    .foregroundColor(p.secondaryText)
            }
            Spacer()
            Button("Re-check") { flasher.detect() }
                .buttonStyle(ThemedButtonStyle(p: p, kind: .secondary))
            Button("Locate…") { locateTool() }
                .buttonStyle(ThemedButtonStyle(p: p, kind: .primary))
        }
        .card(p)
    }

    private func progressRow(_ p: Palette) -> some View {
        HStack(spacing: 12) {
            ThemedProgressBar(value: flasher.progress, p: p)
            Text("\(Int(flasher.progress * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(p.text)
                .frame(width: 44, alignment: .trailing)
            if !flasher.progressLabel.isEmpty && running {
                Text(flasher.progressLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(p.secondaryText)
            }
        }
    }

    // MARK: Log

    private func logPanel(_ p: Palette) -> some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(text: "Output", p: p)
                Spacer()
                statusBadge(p)
                Button("Clear") { flasher.clearLog() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: p.fontDesign))
                    .foregroundColor(p.secondaryText)
                    .padding(.leading, 12)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(p.border).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(flasher.log) { line in
                            Text(line.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(color(for: line.kind, p))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(12)
                }
                .onChange(of: flasher.log.last) { last in
                    if let id = last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .background(p.terminalBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.border, lineWidth: 1))
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func statusBadge(_ p: Palette) -> some View {
        switch flasher.state {
        case .idle:
            EmptyView()
        case .running:
            badge("Running", p.accent)
        case .success:
            badge("Done", p.success)
        case .failed:
            badge("Failed", p.danger)
        case .cancelled:
            badge("Cancelled", p.secondaryText)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }

    private func color(for kind: LogLine.Kind, _ p: Palette) -> Color {
        switch kind {
        case .info: return p.accent
        case .output: return p.terminalText
        case .error: return p.danger
        case .success: return p.success
        }
    }

    // MARK: Actions

    /// Frees the port if the serial monitor is using it, runs the action, then reconnects the monitor.
    private func perform(_ action: @escaping (_ port: String, _ done: @escaping (Bool) -> Void) -> Void) {
        guard let port = scanner.selected else { return }
        let reconnect = monitor.connectedPath == port
        if reconnect { monitor.disconnect() }

        let start = {
            action(port) { _ in
                guard reconnect else { return }
                // Boards with native USB re-enumerate after reset; give the port a moment to return.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    monitor.connect(path: port)
                }
            }
        }
        if reconnect {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: start)
        } else {
            start()
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose firmware binaries (.bin)"
        if panel.runModal() == .OK {
            panel.urls.forEach { flasher.addFile($0) }
        }
    }

    private func locateTool() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the esptool executable"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            flasher.setCustomPath(url)
        }
    }

    private func fileSize(_ url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = attrs?[.size] as? Int else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
