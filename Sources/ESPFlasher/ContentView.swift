import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case flash = "Flash"
    case monitor = "Monitor"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .flash: return "bolt.fill"
        case .monitor: return "terminal"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var scanner: PortScanner
    @State private var tab: AppTab = .flash

    var body: some View {
        let p = theme.palette
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 250)

            Rectangle().fill(p.border).frame(width: 1)

            VStack(spacing: 0) {
                HeaderBar(tab: $tab)
                Rectangle().fill(p.border).frame(height: 1)
                Group {
                    switch tab {
                    case .flash: FlashView()
                    case .monitor: MonitorView()
                    }
                }
            }
            .background(p.background)
        }
        .background(p.background)
        .tint(p.accent)
        .preferredColorScheme(p.colorScheme)
        .frame(minWidth: 960, minHeight: 640)
    }
}

// MARK: - Header

struct HeaderBar: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var scanner: PortScanner
    @Binding var tab: AppTab

    var body: some View {
        let p = theme.palette
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                ForEach(AppTab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon).font(.system(size: 11, weight: .bold))
                            Text(item.rawValue)
                        }
                        .font(.system(size: 13, weight: .semibold, design: p.fontDesign))
                        .foregroundColor(tab == item ? p.onAccent : p.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(tab == item ? p.accent : Color.clear))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(p.panel))
            .overlay(Capsule().stroke(p.border, lineWidth: 1))

            Spacer()

            if let port = scanner.selectedPort {
                HStack(spacing: 8) {
                    StatusDot(color: p.success)
                    Text(port.name)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(p.text)
                }
            } else {
                HStack(spacing: 8) {
                    StatusDot(color: p.secondaryText)
                    Text("No device selected")
                        .font(.system(size: 12, design: p.fontDesign))
                        .foregroundColor(p.secondaryText)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 14)
        .background(p.background)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var scanner: PortScanner

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: 0) {
            // Brand
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(p.onAccent)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(p.accent))
                VStack(alignment: .leading, spacing: 1) {
                    Text("ESP Flasher")
                        .font(.system(size: 15, weight: .bold, design: p.fontDesign))
                        .foregroundColor(p.text)
                    Text("esptool for macOS")
                        .font(.system(size: 11, design: p.fontDesign))
                        .foregroundColor(p.secondaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 38)
            .padding(.bottom, 24)

            // Devices
            HStack {
                SectionLabel(text: "Devices", p: p)
                Text("\(scanner.ports.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(p.secondaryText)
                Spacer()
                Button {
                    scanner.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(p.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Refresh device list")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 4) {
                    if scanner.ports.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No serial devices found")
                                .font(.system(size: 12, weight: .semibold, design: p.fontDesign))
                                .foregroundColor(p.text)
                            Text("Plug in your ESP32 with a data-capable USB cable. Some boards need the CP210x or CH340 driver.")
                                .font(.system(size: 11, design: p.fontDesign))
                                .foregroundColor(p.secondaryText)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(scanner.ports) { port in
                            PortRow(port: port, selected: scanner.selected == port.path) {
                                scanner.selected = port.path
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)

            Toggle(isOn: $scanner.showAll) {
                Text("Show all ports")
                    .font(.system(size: 11, design: p.fontDesign))
                    .foregroundColor(p.secondaryText)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            // Theme switcher
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Theme", p: p)
                HStack(spacing: 6) {
                    ForEach(AppTheme.allCases) { t in
                        Button {
                            theme.theme = t
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: t.icon).font(.system(size: 12))
                                Text(t.label).font(.system(size: 10, weight: .medium, design: p.fontDesign))
                            }
                            .foregroundColor(theme.theme == t ? p.onAccent : p.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(theme.theme == t ? p.accent : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.theme == t ? Color.clear : p.border, lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity)
        .background(p.sidebar)
    }
}

struct PortRow: View {
    @EnvironmentObject var theme: ThemeStore
    let port: SerialPort
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let p = theme.palette
        Button(action: action) {
            HStack(spacing: 10) {
                StatusDot(color: port.isUSB ? p.success : p.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(port.name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(p.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(port.kind)
                        .font(.system(size: 10, design: p.fontDesign))
                        .foregroundColor(p.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? p.accent.opacity(0.16) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? p.accent : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
