import Foundation

@main
struct TranscriptionFileStoreTests {
    static func expect(_ condition: Bool, _ message: String = "Storage assertion failed") {
        precondition(condition, message)
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuHelp-transcription-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TranscriptionFileStore(directory: root.appendingPathComponent("sessions"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try store.createSession(at: date)
        let second = try store.createSession(at: date)
        precondition(first != second, "Two sessions started in the same second must have different TXT files")
        precondition(first.pathExtension == "txt")

        let original = "Olá, reunião! Ação, café e 日本語.\nSegunda frase."
        try store.write(original, to: first)
        expect(try String(contentsOf: first, encoding: .utf8) == original + "\n")
        expect(try Data(contentsOf: second).isEmpty, "Saving one session must not change another")

        // Replacing a longer partial hypothesis must not leave trailing text in the final TXT.
        try store.write("Resultado final.", to: first)
        expect(try String(contentsOf: first, encoding: .utf8) == "Resultado final.\n")
        let attributes = try FileManager.default.attributesOfItem(atPath: first.path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let folderAttributes = try FileManager.default.attributesOfItem(atPath: store.directory.path)
        precondition((folderAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)

        // A failed new destination must leave an existing transcript untouched.
        let blockedStore = TranscriptionFileStore(directory: first)
        do {
            _ = try blockedStore.createSession(at: date)
            preconditionFailure("A regular TXT file cannot also be a destination folder")
        } catch { }
        expect(try String(contentsOf: first, encoding: .utf8) == "Resultado final.\n")

        try store.write("", to: second)
        expect(try Data(contentsOf: second).isEmpty, "Silence must produce an empty transcript")
        print("Passed: separate sessions, UTF-8, atomic replacement, private permissions, failed destination, silence.")
    }
}
