import AppKit
import Combine
import Speech
import UniformTypeIdentifiers

enum TranscriptionState {
    case idle
    case preparing
    case recording
    case stopping
}

@MainActor
final class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()

    @Published private(set) var state: TranscriptionState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var fileURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var audioLevel: Double = 0
    @Published private(set) var hasReceivedAudio = false
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var recognizedSegmentCount = 0
    @Published private(set) var preparationMessage = String(localized: "Preparando captura…")
    @Published var selectedLocaleIdentifier: String {
        didSet {
            UserDefaults.standard.set(selectedLocaleIdentifier, forKey: Self.localeKey)
        }
    }

    let availableLocales: [Locale]
    var isBusy: Bool { state != .idle }
    var isRecording: Bool { state == .recording }

    private static let localeKey = "menuHelp.transcriptionLocale"
    private let fileStore: TranscriptionFileStore
    private var capture: SystemAudioCapture?
    private var engine: (any SpeechTranscriptionBackend)?
    private var timer: Timer?
    private var startedAt: Date?
    private var startedUptime: TimeInterval?
    private var stoppedAt: Date?
    private var stoppedUptime: TimeInterval?
    private var snapshot = SpeechTranscriptionSnapshot(segments: [])
    private var lastSavedTranscript = ""
    private var sessionID: UUID?
    private var startupTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    private init() {
        let locales = SFSpeechRecognizer.supportedLocales().sorted {
            let left = Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
            let right = Locale.current.localizedString(forIdentifier: $1.identifier) ?? $1.identifier
            return left.localizedStandardCompare(right) == .orderedAscending
        }
        availableLocales = locales
        let saved = UserDefaults.standard.string(forKey: Self.localeKey)
        selectedLocaleIdentifier = locales.first(where: { $0.identifier == saved })?.identifier
            ?? locales.first(where: { $0.identifier.replacingOccurrences(of: "_", with: "-") == "pt-BR" })?.identifier
            ?? locales.first(where: { $0.identifier.replacingOccurrences(of: "_", with: "-") == "en-US" })?.identifier
            ?? locales.first?.identifier ?? "pt-BR"

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileStore = TranscriptionFileStore(
            directory: documents.appendingPathComponent("MenuHelp/Transcriptions", isDirectory: true)
        )
    }

    func start() {
        guard state == .idle else { return }
        // A failed disk write must never be erased by starting another session.
        if hasUnsavedChanges {
            persistTranscript(force: true)
            guard !hasUnsavedChanges else { return }
        }
        errorMessage = nil
        preparationMessage = String(localized: "Preparando captura…")
        state = .preparing
        let id = UUID()
        sessionID = id
        startupTask = Task { [weak self] in
            await self?.prepareSession(id: id)
        }
    }

    func stop() {
        guard isBusy, state != .stopping else { return }
        state = .stopping
        freezeRecordingClock()
        startupTask?.cancel()
        stopTask = Task { [weak self] in
            guard let self else { return }
            // A pending authorization/startCapture must settle before stopping its stream.
            await self.startupTask?.value
            await self.finishSession()
        }
    }

    /// App termination waits for pending audio, final recognition and the last disk snapshot.
    func finishBeforeTermination() async -> Bool {
        if isBusy { stop() }
        await stopTask?.value
        persistTranscript(force: true)
        return !hasUnsavedChanges
    }

    func revealFile() {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func saveCopy() {
        guard !transcript.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "MenuHelp.txt"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.fileStore.write(self.transcript, to: url)
                if self.hasUnsavedChanges {
                    self.fileURL = url
                    self.lastSavedTranscript = self.transcript
                    self.hasUnsavedChanges = false
                    self.errorMessage = nil
                }
            } catch {
                self.errorMessage = String(localized: "Não foi possível salvar a cópia. Escolha outra pasta.")
            }
        }
    }

    func openCaptureSettings() {
        openSettings("Privacy_ScreenCapture")
    }

    func openSpeechSettings() {
        openSettings("Privacy_SpeechRecognition")
    }

    private func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func prepareSession(id: UUID) async {
        do {
            let status = await speechAuthorization()
            try Task.checkCancellation()
            guard status == .authorized else {
                throw TranscriptionSetupError.speechPermission
            }
            let newEngine = try await SpeechTranscriptionEngine.make(
                locale: Locale(identifier: selectedLocaleIdentifier),
                onTranscript: { [weak self] snapshot in
                    Task { @MainActor [weak self] in
                        guard let self, self.sessionID == id else { return }
                        self.snapshot = snapshot
                        self.updateHistory()
                    }
                },
                onAudioLevel: { [weak self] level in
                    Task { @MainActor [weak self] in
                        guard let self, self.sessionID == id else { return }
                        self.audioLevel = level
                        self.hasReceivedAudio = true
                    }
                },
                onFailure: { [weak self] message in
                    Task { @MainActor [weak self] in
                        guard let self, self.sessionID == id else { return }
                        self.errorMessage = message
                        self.stop()
                    }
                },
                onPreparation: { [weak self] message in
                    Task { @MainActor [weak self] in
                        guard let self, self.sessionID == id, self.state == .preparing else { return }
                        self.preparationMessage = message
                    }
                }
            )
            if Task.isCancelled {
                _ = await newEngine.finish()
                throw CancellationError()
            }
            let newCapture = SystemAudioCapture(
                onAudio: { sample in newEngine.consume(sample) },
                onFailure: { [weak self] message in
                    Task { @MainActor [weak self] in
                        guard let self, self.sessionID == id else { return }
                        self.errorMessage = message
                        self.stop()
                    }
                },
                onStarted: { timestamp in newEngine.beginRecording(at: timestamp) }
            )
            // Create the destination before capture so a disk failure never loses recognized speech.
            let destination: URL
            do {
                destination = try fileStore.createSession()
            } catch {
                _ = await newEngine.finish()
                throw TranscriptionSetupError.outputFile
            }
            engine = newEngine
            capture = newCapture
            fileURL = destination
            transcript = ""
            lastSavedTranscript = ""
            hasUnsavedChanges = false
            elapsedSeconds = 0
            audioLevel = 0
            hasReceivedAudio = false
            snapshot = SpeechTranscriptionSnapshot(segments: [])
            recognizedSegmentCount = 0
            startedAt = nil
            startedUptime = nil
            stoppedAt = nil
            stoppedUptime = nil
            try await newCapture.start()
            try Task.checkCancellation()
            guard sessionID == id, state == .preparing else { return }
            updateHistory()
            state = .recording
            persistTranscript(force: true)
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == id else { return }
                    self.updateHistory()
                    self.persistTranscript()
                }
            }
        } catch {
            // stop() owns cleanup when preparation was explicitly cancelled.
            guard state != .stopping else { return }
            errorMessage = error.localizedDescription
            await finishSession()
        }
    }

    private func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func finishSession() async {
        state = .stopping
        timer?.invalidate()
        timer = nil
        freezeRecordingClock()
        await capture?.stop()
        if let engine {
            let finalSnapshot = await engine.finish()
            let failure = await engine.failureMessage()
            sessionID = nil
            snapshot = finalSnapshot
            if let failure {
                errorMessage = failure
            }
        }
        // Ignore any already-enqueued partial callback after the final snapshot.
        sessionID = nil
        updateHistory()
        persistTranscript(force: true)
        capture = nil
        engine = nil
        audioLevel = 0
        state = .idle
    }

    private func ensureRecordingClock() {
        guard startedAt == nil, let capture, let start = capture.startedAt else { return }
        startedAt = start
        startedUptime = capture.startedUptime
    }

    private func freezeRecordingClock() {
        ensureRecordingClock()
        guard startedAt != nil, stoppedAt == nil else { return }
        // Final recognition can take seconds; the history ends when capture is stopped.
        stoppedAt = Date()
        stoppedUptime = ProcessInfo.processInfo.systemUptime
    }

    private func updateHistory() {
        ensureRecordingClock()
        guard let startedAt, let startedUptime else { return }
        let elapsed = max(0, (stoppedUptime ?? ProcessInfo.processInfo.systemUptime) - startedUptime)
        elapsedSeconds = Int(elapsed)
        recognizedSegmentCount = snapshot.segments.count
        transcript = TranscriptionHistoryDocument(
            startedAt: startedAt,
            stoppedAt: stoppedAt,
            elapsedTime: elapsed,
            snapshot: snapshot
        ).text
        hasUnsavedChanges = transcript != lastSavedTranscript
    }

    private func persistTranscript(force: Bool = false) {
        guard let fileURL, force || transcript != lastSavedTranscript else { return }
        do {
            try fileStore.write(transcript, to: fileURL)
            lastSavedTranscript = transcript
            hasUnsavedChanges = false
        } catch {
            hasUnsavedChanges = transcript != lastSavedTranscript
            errorMessage = String(localized: "Não foi possível atualizar o TXT. O texto continua nesta janela; use Salvar cópia para preservá-lo.")
            if state == .recording { stop() }
        }
    }
}

private enum TranscriptionSetupError: LocalizedError {
    case speechPermission
    case outputFile

    var errorDescription: String? {
        switch self {
        case .speechPermission:
            String(localized: "Autorize o MenuHelp em Privacidade e Segurança → Reconhecimento de Fala e tente novamente.")
        case .outputFile:
            String(localized: "Não foi possível criar o TXT em Documentos/MenuHelp/Transcriptions. Verifique o espaço livre e a permissão da pasta.")
        }
    }
}
