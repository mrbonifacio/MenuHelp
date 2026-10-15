import Foundation

/// UTF-8 snapshots are replaced atomically so a interrupted write cannot truncate a session.
nonisolated struct TranscriptionFileStore {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func createSession(at date: Date = Date()) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "MenuHelp_\(formatter.string(from: date))_\(UUID().uuidString.prefix(8)).txt"
        let url = directory.appendingPathComponent(name)
        try Data().write(to: url, options: .withoutOverwriting)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    func write(_ transcript: String, to url: URL) throws {
        let text = transcript.isEmpty || transcript.hasSuffix("\n") ? transcript : transcript + "\n"
        try Data(text.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
