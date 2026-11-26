import Foundation

struct FlashFile: Identifiable, Equatable {
    let id = UUID()
    var address: String
    var url: URL
}

/// A way to install esptool that's available on this Mac.
struct InstallMethod: Equatable {
    let title: String          // e.g. "Homebrew"
    let executable: String
    let args: [String]

    var command: String {
        ([URL(fileURLWithPath: executable).lastPathComponent] + args).joined(separator: " ")
    }
}

struct LogLine: Identifiable, Equatable {
    enum Kind { case info, output, error, success }
    let id: Int
    var text: String
    var kind: Kind
}

enum RunState: Equatable {
    case idle, running, success, failed(String), cancelled
}

/// Wraps the `esptool` command-line tool installed on the Mac.
final class Flasher: ObservableObject {
    static let baudRates = [115_200, 230_400, 460_800, 921_600, 1_500_000]

    @Published private(set) var esptoolPath: String?
    @Published private(set) var esptoolVersion: String = ""
    @Published private(set) var isDetecting = true
    /// Best available way to install esptool (nil if neither Homebrew, pipx nor pip is usable).
    @Published private(set) var installMethod: InstallMethod?

    @Published var files: [FlashFile] = []
    @Published var flashBaud: Int {
        didSet { UserDefaults.standard.set(flashBaud, forKey: "flashBaud") }
    }
    @Published var eraseAll = false

    @Published private(set) var state: RunState = .idle
    @Published private(set) var showsProgress = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var progressLabel = ""
    @Published private(set) var log: [LogLine] = []

    private var process: Process?
    private var major = 0
    private var nextLogID = 0
    private var lineBuffer = ""
    private var lastWasFrame = false
    private var cancelled = false

    init() {
        let saved = UserDefaults.standard.integer(forKey: "flashBaud")
        flashBaud = saved > 0 ? saved : 460_800
        detect()
    }

    var isRunning: Bool { state == .running }

    // MARK: - esptool discovery

    func detect() {
        isDetecting = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let path = Flasher.locateEsptool()
            var version = ""
            var major = 0
            var installer: InstallMethod?
            if let path = path {
                let out = Flasher.capture(path, ["version"]) ?? Flasher.capture(path, ["--version"]) ?? ""
                (version, major) = Flasher.parseVersion(out)
            } else {
                installer = Flasher.findInstaller()
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.esptoolPath = path
                self.esptoolVersion = version
                self.major = major
                self.installMethod = installer
                self.isDetecting = false
            }
        }
    }

    func setCustomPath(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: "esptoolPath")
        detect()
    }

    private static func locateEsptool() -> String? {
        let fm = FileManager.default
        if let custom = UserDefaults.standard.string(forKey: "esptoolPath"),
           fm.isExecutableFile(atPath: custom) {
            return custom
        }

        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/esptool", "/opt/homebrew/bin/esptool.py",
            "/usr/local/bin/esptool", "/usr/local/bin/esptool.py",
            "\(home)/.local/bin/esptool", "\(home)/.local/bin/esptool.py"
        ]
        if let hit = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return hit
        }

        // `pip install --user` puts scripts in ~/Library/Python/<version>/bin
        let pyRoot = "\(home)/Library/Python"
        if let versions = try? fm.contentsOfDirectory(atPath: pyRoot) {
            for version in versions.sorted(by: >) {
                for name in ["esptool", "esptool.py"] {
                    let path = "\(pyRoot)/\(version)/bin/\(name)"
                    if fm.isExecutableFile(atPath: path) { return path }
                }
            }
        }

        // Apps launched from Finder don't inherit the shell PATH; ask a login shell.
        for name in ["esptool", "esptool.py"] {
            if let out = capture("/bin/zsh", ["-lc", "command -v \(name)"]) {
                let line = out.split(separator: "\n").map(String.init).last { $0.hasPrefix("/") }
                if let line = line, fm.isExecutableFile(atPath: line) { return line }
            }
        }
        return nil
    }

    /// Picks the easiest installer present: Homebrew, then pipx, then pip (needs Command Line Tools).
    private static func findInstaller() -> InstallMethod? {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        for brew in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where fm.isExecutableFile(atPath: brew) {
            return InstallMethod(title: "Homebrew", executable: brew, args: ["install", "esptool"])
        }
        for pipx in ["/opt/homebrew/bin/pipx", "/usr/local/bin/pipx", "\(home)/.local/bin/pipx"]
        where fm.isExecutableFile(atPath: pipx) {
            return InstallMethod(title: "pipx", executable: pipx, args: ["install", "esptool"])
        }
        // /usr/bin/python3 is only a stub that opens an installer dialog without the Command Line Tools.
        if capture("/usr/bin/xcode-select", ["-p"]) != nil, fm.isExecutableFile(atPath: "/usr/bin/python3") {
            return InstallMethod(title: "pip", executable: "/usr/bin/python3",
                                 args: ["-m", "pip", "install", "--user", "esptool"])
        }
        return nil
    }

    private static func parseVersion(_ output: String) -> (String, Int) {
        let clean = stripANSI(output)
        guard let regex = try? NSRegularExpression(pattern: "(\\d+)\\.(\\d+)(?:\\.(\\d+))?"),
              let m = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
              let whole = Range(m.range, in: clean),
              let majorRange = Range(m.range(at: 1), in: clean) else {
            return ("", 0)
        }
        return (String(clean[whole]), Int(clean[majorRange]) ?? 0)
    }

    private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "\(home)/.local/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        return env
    }

    private static func capture(_ exe: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = environment()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - File list

    func addFile(_ url: URL) {
        guard !files.contains(where: { $0.url == url }) else { return }
        files.append(FlashFile(address: Flasher.guessAddress(for: url), url: url))
    }

    private static func guessAddress(for url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if name.contains("merged") || name.contains("factory") { return "0x0" }
        if name.contains("bootloader") { return "0x1000" }   // ESP32; S3/C3/C6 use 0x0
        if name.contains("partition") { return "0x8000" }
        if name.contains("boot_app0") { return "0xe000" }
        return "0x10000"
    }

    // MARK: - Commands

    func flash(port: String, onFinish: ((Bool) -> Void)? = nil) {
        guard !isRunning else { return }
        guard !files.isEmpty else {
            fail("Add at least one firmware file first.", onFinish)
            return
        }

        var args = ["--port", port, "--baud", String(flashBaud), sub("write_flash")]
        if eraseAll { args.append("--erase-all") }

        for file in files {
            let addr = file.address.trimmingCharacters(in: .whitespaces)
            guard Flasher.isValidAddress(addr) else {
                fail("Invalid flash address “\(file.address)” for \(file.url.lastPathComponent). Use e.g. 0x10000.", onFinish)
                return
            }
            guard FileManager.default.fileExists(atPath: file.url.path) else {
                fail("File not found: \(file.url.path)", onFinish)
                return
            }
            args += [addr, file.url.path]
        }
        showsProgress = true
        run(args, onFinish: onFinish)
    }

    func chipInfo(port: String, onFinish: ((Bool) -> Void)? = nil) {
        guard !isRunning else { return }
        showsProgress = false
        run(["--port", port, "--baud", "115200", sub("flash_id")], onFinish: onFinish)
    }

    func eraseFlash(port: String, onFinish: ((Bool) -> Void)? = nil) {
        guard !isRunning else { return }
        showsProgress = false
        run(["--port", port, "--baud", String(flashBaud), sub("erase_flash")], onFinish: onFinish)
    }

    /// Installs esptool using the best available method, then re-detects it.
    func installEsptool(onFinish: ((Bool) -> Void)? = nil) {
        guard !isRunning, let method = installMethod else { return }
        showsProgress = false
        append(.info, "Installing esptool with \(method.title). This can take a few minutes…")
        let label = URL(fileURLWithPath: method.executable).lastPathComponent
        run(method.args, executable: method.executable, label: label) { [weak self] ok in
            if ok { self?.detect() }
            onFinish?(ok)
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancelled = true
        process?.terminate()
    }

    func clearLog() {
        log.removeAll()
        if !isRunning { state = .idle }
    }

    // esptool v5 renamed subcommands (write_flash -> write-flash); the old names still
    // work but print deprecation warnings, so use the right form for the installed version.
    private func sub(_ name: String) -> String {
        major >= 5 ? name.replacingOccurrences(of: "_", with: "-") : name
    }

    private static func isValidAddress(_ s: String) -> Bool {
        s.range(of: "^(0[xX][0-9a-fA-F]+|[0-9]+)$", options: .regularExpression) != nil
    }

    // MARK: - Process handling

    private func fail(_ message: String, _ onFinish: ((Bool) -> Void)?) {
        append(.error, message)
        state = .failed(message)
        onFinish?(false)
    }

    private func run(_ args: [String], executable: String? = nil, label: String = "esptool",
                     onFinish: ((Bool) -> Void)?) {
        guard let path = executable ?? esptoolPath else {
            fail("esptool was not found. Install it (e.g. `brew install esptool`) or choose its location.", onFinish)
            return
        }

        state = .running
        progress = 0
        progressLabel = ""
        cancelled = false
        lineBuffer = ""
        lastWasFrame = false
        append(.info, "$ \(label) " + args.map(Flasher.shellQuote).joined(separator: " "))

        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.environment = Flasher.environment()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        process = p

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try p.run()
            } catch {
                DispatchQueue.main.async {
                    self?.append(.error, "Could not launch esptool: \(error.localizedDescription)")
                    self?.finish(status: -1, onFinish: onFinish)
                }
                return
            }

            let handle = pipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                DispatchQueue.main.async { self?.consume(chunk) }
            }
            p.waitUntilExit()
            let status = p.terminationStatus
            DispatchQueue.main.async {
                self?.endLine(newline: true)
                self?.finish(status: status, onFinish: onFinish)
            }
        }
    }

    private func finish(status: Int32, onFinish: ((Bool) -> Void)?) {
        process = nil
        let ok = status == 0 && !cancelled

        if cancelled {
            state = .cancelled
            append(.error, "Cancelled.")
        } else if ok {
            state = .success
            if showsProgress { progress = 1 }
            append(.success, "Finished successfully.")
        } else {
            state = .failed("esptool exited with code \(status)")
            append(.error, "esptool exited with code \(status).")
            if let hint = failureHint() { append(.info, hint) }
        }
        onFinish?(ok)
    }

    private func failureHint() -> String? {
        let tail = log.suffix(40).map { $0.text.lowercased() }.joined(separator: "\n")
        if tail.contains("failed to connect") || tail.contains("no serial data received") {
            return "Tip: hold the BOOT button while connecting (release once “Writing” starts), try a data-capable USB cable, or lower the baud rate."
        }
        if tail.contains("resource busy") || tail.contains("could not exclusively lock") || tail.contains("permission denied") {
            return "Tip: the port is in use. Disconnect the serial monitor or close other apps using it."
        }
        if tail.contains("no such file") && tail.contains("/dev/") {
            return "Tip: the device disappeared. Replug the board and refresh the device list."
        }
        return nil
    }

    // MARK: - Output parsing

    private func consume(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n": endLine(newline: true)
            case "\r": endLine(newline: false)
            default: lineBuffer.unicodeScalars.append(scalar)
            }
        }
    }

    private func endLine(newline: Bool) {
        let line = Flasher.stripANSI(lineBuffer).trimmingCharacters(in: .whitespaces)
        lineBuffer = ""

        if line.isEmpty {
            if newline { lastWasFrame = false }
            return
        }

        let isProgress = parseProgress(line)
        let isFrame = isProgress || !newline

        if isFrame {
            if lastWasFrame, !log.isEmpty {
                log[log.count - 1].text = line
            } else {
                append(.output, line)
            }
            lastWasFrame = true
        } else {
            append(.output, line)
            lastWasFrame = false
        }
    }

    /// Returns true if the line was a "Writing at 0x… 12.3 %" progress update.
    private func parseProgress(_ line: String) -> Bool {
        guard line.contains("Writing"), line.contains("%"),
              let regex = try? NSRegularExpression(pattern: "(\\d{1,3}(?:\\.\\d+)?)\\s*%"),
              let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r = Range(m.range(at: 1), in: line),
              let pct = Double(line[r]) else {
            return false
        }
        progress = min(1, max(0, pct / 100))
        if let addr = line.range(of: "0x[0-9a-fA-F]+", options: .regularExpression) {
            progressLabel = "Writing at \(line[addr])"
        }
        return true
    }

    private func append(_ kind: LogLine.Kind, _ text: String) {
        log.append(LogLine(id: nextLogID, text: text, kind: kind))
        nextLogID += 1
        if log.count > 1500 { log.removeFirst(log.count - 1500) }
    }

    private static let ansiRegex = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")

    private static func stripANSI(_ s: String) -> String {
        ansiRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    private static func shellQuote(_ s: String) -> String {
        s.contains(" ") ? "\"\(s)\"" : s
    }
}
