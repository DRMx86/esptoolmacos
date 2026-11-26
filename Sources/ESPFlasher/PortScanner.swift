import Foundation

struct SerialPort: Identifiable, Hashable {
    let path: String
    var id: String { path }

    /// "/dev/cu.usbserial-0001" -> "usbserial-0001"
    var name: String {
        path.hasPrefix("/dev/cu.") ? String(path.dropFirst("/dev/cu.".count)) : path
    }

    /// USB-UART bridges and native USB chips typically used with ESP32 boards.
    var isUSB: Bool {
        let n = name.lowercased()
        return n.contains("usb") || n.contains("slab") || n.contains("wch") || n.contains("ftdi")
    }

    var kind: String {
        let n = name.lowercased()
        if n.contains("slab") { return "CP210x USB-UART" }
        if n.contains("wch") { return "CH340/CH9102 USB-UART" }
        if n.contains("usbmodem") { return "USB CDC (native)" }
        if n.contains("usbserial") { return "USB serial" }
        if n.contains("bluetooth") { return "Bluetooth" }
        return "Serial"
    }
}

/// Lists /dev/cu.* devices and keeps the list fresh while the app is open.
final class PortScanner: ObservableObject {
    @Published private(set) var ports: [SerialPort] = []
    @Published var selected: String?
    @Published var showAll: Bool = false {
        didSet { refresh() }
    }

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        var found = names
            .filter { $0.hasPrefix("cu.") }
            .map { SerialPort(path: "/dev/" + $0) }

        if !showAll {
            found = found.filter { $0.isUSB }
        }

        found.sort { a, b in
            if a.isUSB != b.isUSB { return a.isUSB }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        if found != ports { ports = found }

        if let s = selected, !found.contains(where: { $0.path == s }) {
            selected = nil
        }
        if selected == nil {
            selected = found.first(where: { $0.isUSB })?.path
        }
    }

    var selectedPort: SerialPort? {
        ports.first { $0.path == selected }
    }
}
