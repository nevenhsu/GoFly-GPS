import Foundation

#if canImport(Darwin)
import Darwin
#endif
#if canImport(os)
import os
#endif

/// Fixed categories so device logs can be filtered by `subsystem` and `category`.
public enum DiagnosticsCategory: String, Sendable, CaseIterable {
    case movement
    case device
    case background
    case tunnel
}

public enum DiagnosticsLevel: String, Sendable, Comparable {
    case debug
    case info
    /// `.notice` and above survive in the device's persistent log. Use them for
    /// every event that must still be available after a crash or a stopped run.
    case notice
    case error

    private var rank: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .notice: 2
        case .error: 3
        }
    }

    public static func < (lhs: DiagnosticsLevel, rhs: DiagnosticsLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// One bounded, privacy-checked field. Never pass a raw FFI message: those can
/// contain pairing material, device identifiers or local paths.
public enum DiagnosticsField: Sendable, Equatable {
    case code(Int32)
    case count(Int)
    case milliseconds(Double)
    case number(Double, digits: Int)
    case text(String)
    case flag(Bool)
    /// Latitude/longitude are rounded to three decimals (~110 m) on purpose.
    case coordinate(latitude: Double, longitude: Double)

    var lineValue: String {
        switch self {
        case .code(let value): return String(value)
        case .count(let value): return String(value)
        case .milliseconds(let value): return Self.fixed(value, 1)
        case .number(let value, let digits): return Self.fixed(value, digits)
        case .text(let value): return Self.sanitized(value)
        case .flag(let value): return value ? "1" : "0"
        case .coordinate(let latitude, let longitude):
            return "\(Self.fixed(latitude, 3)),\(Self.fixed(longitude, 3))"
        }
    }

    var jsonValue: String {
        switch self {
        case .code, .count, .milliseconds, .number, .flag:
            return lineValue
        case .text(let value):
            return "\"\(Self.jsonEscaped(Self.sanitized(value)))\""
        case .coordinate:
            return "\"\(lineValue)\""
        }
    }

    static func fixed(_ value: Double, _ digits: Int) -> String {
        guard value.isFinite else { return "0" }
        let places = max(0, min(digits, 6))
        return String(format: "%.\(places)f", arguments: [value])
    }

    /// Field values are bounded and single-line so one event is always one
    /// JSONL record and one log line.
    static func sanitized(_ value: String) -> String {
        let collapsed = value.unicodeScalars.map { scalar -> Character in
            if scalar == "\n" || scalar == "\r" || scalar == "\t" { return " " }
            if scalar.value < 0x20 || scalar.value == 0x7F { return " " }
            return Character(scalar)
        }
        let text = String(collapsed)
        return text.count > 96 ? String(text.prefix(96)) : text
    }

    static func jsonEscaped(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count + 8)
        for character in value {
            switch character {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            default: result.append(character)
            }
        }
        return result
    }
}

public struct DiagnosticsEvent: Sendable, Equatable {
    public let timestamp: Date
    public let category: DiagnosticsCategory
    public let level: DiagnosticsLevel
    public let name: String
    public let fields: [String: DiagnosticsField]

    public init(timestamp: Date = Date(), category: DiagnosticsCategory,
                level: DiagnosticsLevel = .debug, name: String,
                fields: [String: DiagnosticsField] = [:]) {
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.name = DiagnosticsField.sanitized(name)
        self.fields = fields
    }
}

/// The single rendered form of one event. `line` feeds `os.Logger`; `json` is
/// one JSONL record in the on-device ring file.
public struct DiagnosticsRecord: Sendable, Equatable {
    public let event: DiagnosticsEvent
    public let line: String
    public let json: String

    public init(event: DiagnosticsEvent) {
        self.event = event
        let orderedKeys = event.fields.keys.sorted()
        let pairs = orderedKeys.map { "\($0)=\(event.fields[$0]!.lineValue)" }
        line = (["\(event.level.rawValue.uppercased()) \(event.category.rawValue) \(event.name)"]
            + pairs).joined(separator: " ")
        let jsonFields = orderedKeys.map { "\"\($0)\":\(event.fields[$0]!.jsonValue)" }
            .joined(separator: ",")
        let epoch = DiagnosticsField.fixed(event.timestamp.timeIntervalSince1970, 3)
        let uptime = DiagnosticsField.fixed(ProcessInfo.processInfo.systemUptime, 3)
        json = "{\"t\":\(epoch),\"up\":\(uptime),\"cat\":\"\(event.category.rawValue)\","
            + "\"lvl\":\"\(event.level.rawValue)\",\"name\":\"\(event.name)\","
            + "\"fields\":{\(jsonFields)}}"
    }
}

public protocol DiagnosticsSink: AnyObject, Sendable {
    func write(_ record: DiagnosticsRecord)
}

/// Fan-out point for diagnostics. Every event goes to `os.Logger` (subsystem
/// `com.neven.gofly`) and to the on-device JSONL ring file, so evidence survives
/// an unplugged phone. Delivery happens on one serial queue; callers only build
/// the record.
public final class Diagnostics: @unchecked Sendable {
    public static let shared = Diagnostics()
    public static let subsystem = "com.neven.gofly"
    public static let filename = "gofly.jsonl"
    public static let maximumFileBytes = 2 * 1024 * 1024

    private let queue = DispatchQueue(label: "com.neven.gofly.diagnostics", qos: .utility)
    private let lock = NSLock()
    private var extraSinks: [any DiagnosticsSink] = []
    private var fileSink: DiagnosticsFileSink?
    private var started = false

    init() {}

    public var isStarted: Bool {
        lock.withLock { started }
    }

    /// Idempotent. Defaults to `Library/Application Support/Diagnostics/`.
    /// Idempotent: the first call decides the file location for the process.
    public func start(directory: URL? = nil, maximumBytes: Int = Diagnostics.maximumFileBytes) {
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        fileSink = DiagnosticsFileSink(directory: directory ?? Self.defaultDirectory(),
                                       filename: Self.filename, maximumBytes: maximumBytes)
        lock.unlock()
        record("diagnostics.started", category: .device, level: .notice, [
            "app": .text(Self.bundleValue("CFBundleShortVersionString")),
            "build": .text(Self.bundleValue("CFBundleVersion")),
            "os": .text(ProcessInfo.processInfo.operatingSystemVersionString),
            "cap_bytes": .count(maximumBytes)
        ])
    }

    public func record(_ name: String, category: DiagnosticsCategory,
                       level: DiagnosticsLevel = .debug,
                       _ fields: [String: DiagnosticsField] = [:]) {
        let record = DiagnosticsRecord(event: DiagnosticsEvent(
            category: category, level: level, name: name, fields: fields))
        let data = Data((record.json + "\n").utf8)
        queue.async { [self] in
            lock.lock()
            let sink = fileSink
            let sinks = extraSinks
            lock.unlock()
            sink?.append(data)
            writeToOSLog(record)
            for extra in sinks { extra.write(record) }
        }
    }

    /// Test and export helper: waits for every queued delivery to finish.
    public func flush() {
        queue.sync {}
    }

    public func attach(_ sink: any DiagnosticsSink) {
        lock.withLock { extraSinks.append(sink) }
    }

    public func detach(_ sink: any DiagnosticsSink) {
        lock.withLock { extraSinks.removeAll { $0 === sink } }
    }

    public func detachAllSinks() {
        lock.withLock { extraSinks.removeAll() }
    }

    public var fileURL: URL? {
        lock.withLock { fileSink?.url }
    }

    public var fileByteCount: Int {
        queue.sync { lock.withLock { fileSink?.size ?? 0 } }
    }

    /// Removes the on-device ring file and resets the tracked size to zero.
    public func clear() {
        queue.sync {
            let sink = lock.withLock { fileSink }
            sink?.clear()
        }
    }

    /// Copies the ring file plus a short header into a shareable temporary file.
    public func export(directory: URL? = nil) throws -> URL {
        queue.sync {}
        lock.lock()
        let sink = fileSink
        let header = exportHeader(from: sink)
        lock.unlock()
        var data = Data((header + "\n").utf8)
        if let body = sink?.load() { data.append(body) }
        let stamp = Self.exportStamp(Date())
        let file = AtomicFile(directory: directory ?? FileManager.default.temporaryDirectory,
                              filename: "gofly-diagnostics-\(stamp).jsonl",
                              maximumBytes: 8 * 1024 * 1024)
        try file.saveData(data)
        return file.url
    }

    private func exportHeader(from sink: DiagnosticsFileSink?) -> String {
        let app = Self.bundleValue("CFBundleShortVersionString")
        let build = Self.bundleValue("CFBundleVersion")
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let rows = [
            "# GoFly diagnostics",
            "# exported_at_epoch=\(DiagnosticsField.fixed(Date().timeIntervalSince1970, 3))",
            "# app=\(app) build=\(build)",
            "# os=\(os)",
            "# file=\(Self.filename) bytes=\(sink?.size ?? 0) cap=\(sink?.maximumBytes ?? 0)",
            "# format=jsonl one event per line; fields are bounded, coordinates rounded to 3 decimals",
            "# local_time=\(Self.localStamp(Date()))"
        ]
        return rows.joined(separator: "\n")
    }

    private func writeToOSLog(_ record: DiagnosticsRecord) {
        #if canImport(os)
        let logger = Self.loggers[record.event.category]
            ?? Logger(subsystem: Self.subsystem, category: record.event.category.rawValue)
        switch record.event.level {
        case .debug: logger.debug("\(record.line, privacy: .public)")
        case .info: logger.info("\(record.line, privacy: .public)")
        case .notice: logger.notice("\(record.line, privacy: .public)")
        case .error: logger.error("\(record.line, privacy: .public)")
        }
        #endif
    }

    #if canImport(os)
    private static let loggers: [DiagnosticsCategory: Logger] = Dictionary(
        uniqueKeysWithValues: DiagnosticsCategory.allCases.map {
            ($0, Logger(subsystem: subsystem, category: $0.rawValue))
        })
    #endif

    static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private static func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }

    private static func exportStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func localStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter.string(from: date)
    }
}

/// Append-only JSONL file with a hard byte cap. On overflow the oldest half is
/// dropped at a line boundary and the file is replaced atomically, so a long
/// session keeps its most recent evidence instead of growing without bound.
final class DiagnosticsFileSink: @unchecked Sendable {
    let directory: URL
    let filename: String
    let maximumBytes: Int
    private var descriptor: Int32 = -1
    private var byteCount = 0
    private var directoryUnavailable = false

    init(directory: URL, filename: String, maximumBytes: Int) {
        self.directory = directory.standardizedFileURL
        self.filename = filename
        self.maximumBytes = max(0, maximumBytes)
    }

    deinit { close() }

    var url: URL { directory.appendingPathComponent(filename) }
    var size: Int { byteCount }

    func append(_ data: Data) {
        guard maximumBytes > 0, !data.isEmpty else { return }
        ensureDirectory()
        guard !directoryUnavailable else { return }
        if descriptor < 0 { openFile() }
        guard descriptor >= 0 else { return }
        if byteCount + data.count > maximumBytes {
            compact()
            if descriptor < 0 { openFile() }
        }
        guard descriptor >= 0 else { return }
        let written = writeAll(data)
        if written > 0 { byteCount += written }
    }

    func load() -> Data? {
        try? AtomicFile(directory: directory, filename: filename, maximumBytes: maximumBytes)
            .loadData()
    }

    func clear() {
        close()
        try? FileManager.default.removeItem(at: url)
        byteCount = 0
    }

    private func writeAll(_ data: Data) -> Int {
        #if canImport(Darwin)
        return data.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress, buffer.count > 0 else { return 0 }
            var offset = 0
            while offset < buffer.count {
                let result = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if result < 0 {
                    if errno == EINTR { continue }
                    return -1
                }
                offset += result
            }
            return offset
        }
        #else
        return -1
        #endif
    }

    private func ensureDirectory() {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue { directoryUnavailable = true }
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            directoryUnavailable = true
        }
    }

    private func openFile() {
        #if canImport(Darwin)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        fchmod(fd, 0o600)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path)
        #endif
        var info = stat()
        byteCount = fstat(fd, &info) == 0 && info.st_size > 0 ? Int(info.st_size) : 0
        descriptor = fd
        #endif
    }

    private func compact() {
        close()
        guard let existing = load(), !existing.isEmpty else { return }
        let keep = max(1, maximumBytes / 2)
        let tail = existing.count > keep ? existing.suffix(keep) : existing
        let trimmed: Data
        if let newline = tail.firstIndex(of: 0x0A) {
            trimmed = Data(tail[tail.index(after: newline)...])
        } else {
            trimmed = Data(tail)
        }
        let marker = Data(("{\"t\":\(DiagnosticsField.fixed(Date().timeIntervalSince1970, 3)),"
            + "\"cat\":\"device\",\"lvl\":\"notice\",\"name\":\"diagnostics.ring.trimmed\","
            + "\"fields\":{\"kept_bytes\":\(trimmed.count)}}\n").utf8)
        var output = marker
        output.append(trimmed)
        let file = AtomicFile(directory: directory, filename: filename, maximumBytes: maximumBytes)
        do {
            try file.saveData(output)
        } catch {
            // Keep the old file rather than losing evidence; the next append retries.
            openFile()
            return
        }
        openFile()
    }

    private func close() {
        #if canImport(Darwin)
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
        #endif
    }
}
