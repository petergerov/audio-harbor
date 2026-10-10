import Foundation

/// Everything goes to `<run folder>/log.txt`, so a run can be sent back. Set the static
/// configuration before the first message.
public final class Log: @unchecked Sendable {
    /// Where the run folder is made; default: the current directory.
    public static var baseDirectory: URL?
    /// Run folder name before the time stamp; default: the tool's name.
    public static var folderPrefix: String?
    /// `say()` also prints to the terminal. Off in the guided test, where only `tell()` does.
    public static var echo = true

    public static let shared = Log()

    public let directory: URL
    private let file: FileHandle
    private let lock = NSLock()
    private let start = Date()

    private init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = (Log.folderPrefix ?? URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent)
            + "-" + formatter.string(from: Date())
        let base = Log.baseDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var directory = base.appendingPathComponent(name)
        if (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) == nil {
            // Not writable there (run from a read-only place): the home folder always is.
            directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.directory = directory
        let url = directory.appendingPathComponent("log.txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        file = try! FileHandle(forWritingTo: url)
    }

    /// A time-stamped line in the log; on the terminal too when `terminal` is set (`plain`: without the stamp).
    public func write(_ message: String, terminal: Bool, plain: Bool = false) {
        let stamped = String(format: "[%8.3f] ", Date().timeIntervalSince(start)) + message + "\n"
        lock.lock()
        defer { lock.unlock() }
        if terminal { FileHandle.standardOutput.write(Data((plain ? message + "\n" : stamped).utf8)) }
        file.write(Data(stamped.utf8))
    }

    public func save(_ name: String, _ data: Data, quiet: Bool = false) {
        try? data.write(to: directory.appendingPathComponent(name))
        if !quiet { write("saved \(name) (\(data.count) bytes)", terminal: Log.echo) }
    }
}

/// Detail for the log; on the terminal only while `Log.echo` is on.
public func say(_ message: String) { Log.shared.write(message, terminal: Log.echo) }

/// For the person at the keyboard: always on the terminal, without a time stamp.
public func tell(_ message: String) { Log.shared.write(message, terminal: true, plain: true) }

public struct ToolError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}
