import Foundation
import Darwin

enum LineEnding: String, CaseIterable, Identifiable {
    case none = "No line ending"
    case lf = "Newline"
    case cr = "Carriage return"
    case crlf = "Both NL & CR"

    var id: String { rawValue }

    var suffix: String {
        switch self {
        case .none: return ""
        case .lf: return "\n"
        case .cr: return "\r"
        case .crlf: return "\r\n"
        }
    }
}

// ioctl request codes (macOS). These are _IO/_IOW macros that Swift can't import.
private let IOSSIOSPEED_REQ: UInt = 0x8008_5402   // _IOW('T', 2, speed_t)
private let TIOCMBIS_REQ: UInt = 0x8004_746C      // _IOW('t', 108, int)
private let TIOCMBIC_REQ: UInt = 0x8004_746B      // _IOW('t', 107, int)
private let TIOCM_DTR_BIT: Int32 = 0x002
private let TIOCM_RTS_BIT: Int32 = 0x004

/// A minimal serial terminal built on POSIX termios + GCD.
final class SerialMonitor: ObservableObject {
    static let baudRates = [
        9600, 19200, 38400, 57600, 74880, 115200, 230400,
        460800, 921600, 1_500_000, 2_000_000
    ]

    @Published private(set) var baud: Int
    @Published private(set) var isConnected = false
    @Published private(set) var connectedPath: String?
    @Published var errorMessage: String?
    /// Bumped whenever there is new text for the terminal view to pick up.
    @Published private(set) var revision = 0
    private(set) var clearToken = 0

    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let ioQueue = DispatchQueue(label: "esp.serial.read")
    private let writeQueue = DispatchQueue(label: "esp.serial.write")

    // Accessed on ioQueue only
    private var partial = Data()

    // Accessed on main only
    private var pendingText = ""
    private var fullLog = ""
    private var flushScheduled = false

    init() {
        let saved = UserDefaults.standard.integer(forKey: "monitorBaud")
        baud = saved > 0 ? saved : 115_200
    }

    deinit { source?.cancel() }

    var logText: String { fullLog }

    // MARK: Connection

    func connect(path: String) {
        disconnect()
        errorMessage = nil

        let newFD = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard newFD >= 0 else {
            errorMessage = "Could not open \(path): \(String(cString: strerror(errno)))"
            return
        }
        guard configure(fd: newFD, baud: baud) else {
            close(newFD)
            errorMessage = "Could not configure \(path) at \(baud) baud."
            return
        }

        fd = newFD
        let src = DispatchSource.makeReadSource(fileDescriptor: newFD, queue: ioQueue)
        src.setEventHandler { [weak self] in self?.readAvailable(newFD) }
        src.setCancelHandler { close(newFD) }
        source = src
        src.resume()

        connectedPath = path
        isConnected = true
        let name = path.replacingOccurrences(of: "/dev/", with: "")
        appendSystem("— connected to \(name) @ \(baud) baud —\n")
    }

    func disconnect() {
        guard fd >= 0 else {
            isConnected = false
            connectedPath = nil
            return
        }
        source?.cancel()   // cancel handler closes the descriptor
        source = nil
        fd = -1
        ioQueue.async { [weak self] in self?.partial.removeAll() }
        isConnected = false
        connectedPath = nil
        appendSystem("— disconnected —\n")
    }

    func setBaud(_ newBaud: Int) {
        baud = newBaud
        UserDefaults.standard.set(newBaud, forKey: "monitorBaud")
        if fd >= 0 {
            if !configure(fd: fd, baud: newBaud) {
                errorMessage = "Could not switch to \(newBaud) baud."
            } else {
                appendSystem("— baud rate set to \(newBaud) —\n")
            }
        }
    }

    // MARK: Output

    func clear() {
        pendingText = ""
        fullLog = ""
        clearToken += 1
        revision &+= 1
    }

    /// Called by the terminal view to collect text that arrived since the last update.
    func takePending() -> String {
        let text = pendingText
        pendingText = ""
        return text
    }

    // MARK: Input / control lines

    func send(_ text: String, ending: LineEnding) {
        guard fd >= 0 else { return }
        let target = fd
        let bytes = Array((text + ending.suffix).utf8)
        guard !bytes.isEmpty else { return }
        writeQueue.async {
            var offset = 0
            while offset < bytes.count {
                let n = bytes[offset...].withUnsafeBytes { write(target, $0.baseAddress, $0.count) }
                if n > 0 {
                    offset += n
                } else if n < 0 && (errno == EAGAIN || errno == EINTR) {
                    usleep(2_000)
                } else {
                    break
                }
            }
        }
    }

    /// Pulses RTS (wired to EN on most dev boards) to reboot the ESP32.
    func resetBoard() {
        guard fd >= 0 else { return }
        let target = fd
        appendSystem("— reset (RTS pulse) —\n")
        writeQueue.async {
            SerialMonitor.setLine(target, TIOCM_DTR_BIT, on: false)  // IO0 high
            SerialMonitor.setLine(target, TIOCM_RTS_BIT, on: true)   // EN low
            usleep(120_000)
            SerialMonitor.setLine(target, TIOCM_RTS_BIT, on: false)  // EN high
        }
    }

    private static func setLine(_ fd: Int32, _ bit: Int32, on: Bool) {
        var flags = bit
        _ = ioctl(fd, on ? TIOCMBIS_REQ : TIOCMBIC_REQ, &flags)
    }

    // MARK: Internals

    private func configure(fd: Int32, baud: Int) -> Bool {
        var t = termios()
        if tcgetattr(fd, &t) != 0 { return false }
        cfmakeraw(&t)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        t.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CSIZE)
        t.c_cflag |= tcflag_t(CS8)
        cfsetspeed(&t, speed_t(B115200))
        if tcsetattr(fd, TCSANOW, &t) != 0 { return false }

        // IOSSIOSPEED supports arbitrary rates (74880, 921600, 1500000, ...).
        var speed = speed_t(baud)
        if ioctl(fd, IOSSIOSPEED_REQ, &speed) == -1 {
            cfsetspeed(&t, speed_t(baud))
            if tcsetattr(fd, TCSANOW, &t) != 0 { return false }
        }
        tcflush(fd, TCIOFLUSH)
        return true
    }

    private func readAvailable(_ descriptor: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = read(descriptor, &buffer, buffer.count)
        if n > 0 {
            handle(Data(buffer[0..<n]))
        } else if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) {
            // Device unplugged or closed.
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.fd == descriptor else { return }
                self.errorMessage = "Device disconnected."
                self.disconnect()
            }
        }
    }

    private func handle(_ data: Data) {
        partial.append(data)

        // Decode the longest valid UTF-8 prefix; keep an incomplete tail for the next read.
        var end = partial.count
        var decoded: String?
        while end > 0 && partial.count - end <= 3 {
            if let s = String(data: partial.prefix(end), encoding: .utf8) {
                decoded = s
                break
            }
            end -= 1
        }

        let text: String
        if let decoded = decoded {
            text = decoded
            partial = Data(partial.dropFirst(end))
        } else {
            // Garbage (e.g. wrong baud rate). Decode leniently so the user sees something.
            text = String(decoding: partial, as: UTF8.self)
            partial.removeAll()
        }

        guard !text.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.append(SerialMonitor.sanitize(text))
        }
    }

    private static let ansiRegex = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")

    private static func sanitize(_ input: String) -> String {
        var text = input.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "")
        let range = NSRange(text.startIndex..., in: text)
        return ansiRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private func appendSystem(_ text: String) {
        // Make sure system notes start on their own line.
        let prefix = (pendingText.isEmpty && fullLog.isEmpty) || fullLog.hasSuffix("\n") || pendingText.hasSuffix("\n") ? "" : "\n"
        append(prefix + text)
    }

    private func append(_ text: String) {
        guard !text.isEmpty else { return }
        pendingText += text
        fullLog += text
        if fullLog.count > 1_000_000 {
            fullLog = String(fullLog.suffix(500_000))
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.flushScheduled = false
            self?.revision &+= 1
        }
    }
}
