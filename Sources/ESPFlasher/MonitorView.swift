import SwiftUI
import AppKit

struct MonitorView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var scanner: PortScanner
    @EnvironmentObject var monitor: SerialMonitor
    @EnvironmentObject var flasher: Flasher

    @State private var input = ""
    @State private var ending: LineEnding = .lf
    @State private var autoscroll = true

    var body: some View {
        let p = theme.palette
        VStack(spacing: 14) {
            controls(p)

            if let error = monitor.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                    Spacer()
                    Button {
                        monitor.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12, design: p.fontDesign))
                .foregroundColor(p.danger)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.danger.opacity(0.6), lineWidth: 1))
            }

            TerminalView(monitor: monitor, palette: p, autoscroll: autoscroll)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.border, lineWidth: 1))
                .frame(maxHeight: .infinity)

            inputRow(p)
        }
        .padding(24)
    }

    // MARK: Controls

    private func controls(_ p: Palette) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Baud rate", p: p)
                ThemedMenu(
                    p: p,
                    options: SerialMonitor.baudRates,
                    selection: Binding(
                        get: { monitor.baud },
                        set: { monitor.setBaud($0) }
                    ),
                    label: { String($0) }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Connection", p: p)
                if monitor.isConnected {
                    Button {
                        monitor.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "bolt.slash.fill")
                    }
                    .buttonStyle(ThemedButtonStyle(p: p, kind: .danger))
                } else {
                    Button {
                        if let port = scanner.selected { monitor.connect(path: port) }
                    } label: {
                        Label("Connect", systemImage: "bolt.fill")
                    }
                    .buttonStyle(ThemedButtonStyle(p: p, kind: .primary))
                    .disabled(scanner.selected == nil || flasher.isRunning)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Toggle(isOn: $autoscroll) {
                    Text("Autoscroll")
                        .font(.system(size: 11, design: p.fontDesign))
                        .foregroundColor(p.secondaryText)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Button {
                    monitor.resetBoard()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(ThemedButtonStyle(p: p, kind: .secondary))
                .disabled(!monitor.isConnected)
                .help("Pulse RTS to reboot the board")

                Button {
                    monitor.clear()
                } label: {
                    Label("Clear", systemImage: "eraser")
                }
                .buttonStyle(ThemedButtonStyle(p: p, kind: .secondary))

                Button {
                    saveLog()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(ThemedButtonStyle(p: p, kind: .secondary))
            }
        }
        .card(p)
    }

    private func inputRow(_ p: Palette) -> some View {
        HStack(spacing: 10) {
            TextField("Send to device…", text: $input)
                .themedField(p)
                .onSubmit(send)
                .disabled(!monitor.isConnected)

            ThemedMenu(
                p: p,
                options: LineEnding.allCases,
                selection: $ending,
                label: { $0.rawValue }
            )

            Button(action: send) {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(ThemedButtonStyle(p: p, kind: .primary))
            .disabled(!monitor.isConnected)
        }
    }

    // MARK: Actions

    private func send() {
        guard monitor.isConnected else { return }
        monitor.send(input, ending: ending)
        input = ""
    }

    private func saveLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "esp32-serial-log.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try monitor.logText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                monitor.errorMessage = "Could not save log: \(error.localizedDescription)"
            }
        }
    }
}
