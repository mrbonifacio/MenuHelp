import CoreMedia
import Foundation
import ScreenCaptureKit

/// Streams the Mac's playback audio. No screen output or recording file is registered.
@MainActor
final class SystemAudioCapture {
    private let onAudio: @Sendable (CMSampleBuffer) -> Void
    private let onFailure: @Sendable (String) -> Void
    private let onStarted: @Sendable (CMTime) -> Void
    private(set) var startedAt: Date?
    private(set) var startedUptime: TimeInterval?
    private(set) var stoppedAt: Date?
    private(set) var stoppedUptime: TimeInterval?
    private let sampleQueue = DispatchQueue(
        label: "com.menuhelp.transcription.system-audio",
        qos: .userInitiated
    )

    private var sessionID: UUID?
    private var stream: SCStream?
    private var output: SystemAudioStreamOutput?

    init(
        onAudio: @escaping @Sendable (CMSampleBuffer) -> Void,
        onFailure: @escaping @Sendable (String) -> Void,
        onStarted: @escaping @Sendable (CMTime) -> Void = { _ in }
    ) {
        self.onAudio = onAudio
        self.onFailure = onFailure
        self.onStarted = onStarted
    }

    func start() async throws {
        guard sessionID == nil else { return }
        let sessionID = UUID()
        self.sessionID = sessionID
        var pendingStream: SCStream?
        var pendingOutput: SystemAudioStreamOutput?

        do {
            // ScreenCaptureKit presents the native Screen & System Audio Recording
            // authorization flow when access has not yet been granted.
            let content = try await SCShareableContent.current
            try Task.checkCancellation()
            guard self.sessionID == sessionID else { throw CancellationError() }
            guard let display = content.displays.first else {
                throw SystemAudioCaptureError.noDisplay
            }

            // An empty exclusion list includes playback from every application.
            let filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 16_000
            configuration.channelCount = 1
            configuration.captureMicrophone = false
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
            configuration.queueDepth = 3
            configuration.showsCursor = false

            let output = SystemAudioStreamOutput(onAudio: onAudio, onFailure: onFailure)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
            pendingStream = stream
            pendingOutput = output

            // Only audio samples are delivered to the app. No screen buffers are
            // requested, retained, analyzed, or written to disk.
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: sampleQueue)
            self.stream = stream
            self.output = output
            startedAt = Date()
            startedUptime = ProcessInfo.processInfo.systemUptime
            stoppedAt = nil
            stoppedUptime = nil
            onStarted(CMClockGetTime(CMClockGetHostTimeClock()))
            try await stream.startCapture()
            try Task.checkCancellation()
            guard self.sessionID == sessionID else { throw CancellationError() }
        } catch {
            pendingOutput?.deactivate()
            if let pendingStream {
                if let pendingOutput {
                    try? pendingStream.removeStreamOutput(pendingOutput, type: .audio)
                }
                try? await pendingStream.stopCapture()
            }
            if self.sessionID == sessionID {
                self.sessionID = nil
                stream = nil
                output = nil
            }
            if error is CancellationError { throw error }
            throw SystemAudioCaptureError.from(error)
        }
    }

    func stop() async {
        if startedAt != nil, stoppedAt == nil {
            stoppedAt = Date()
            stoppedUptime = ProcessInfo.processInfo.systemUptime
        }
        // Invalidate a pending start before its next suspension point completes.
        sessionID = nil
        let currentStream = stream
        let currentOutput = output
        stream = nil
        output = nil
        // Suppress intentional shutdown errors while keeping queued audio live.
        currentOutput?.prepareForStop()
        guard let currentStream else { return }
        try? await currentStream.stopCapture()
        // Forward all callbacks queued before capture stopped, then let the owner
        // enqueue speech finalization on its own serial recognition queue.
        await withCheckedContinuation { continuation in
            sampleQueue.async { continuation.resume() }
        }
        currentOutput?.deactivate()
        if let currentOutput {
            try? currentStream.removeStreamOutput(currentOutput, type: .audio)
        }
    }
}

/// ScreenCaptureKit invokes these callbacks off the main actor. Mutable state is
/// guarded by a lock; media is forwarded synchronously on the serial sample queue.
nonisolated private final class SystemAudioStreamOutput: NSObject, SCStreamOutput,
    SCStreamDelegate, @unchecked Sendable {
    private let onAudio: @Sendable (CMSampleBuffer) -> Void
    private let onFailure: @Sendable (String) -> Void
    private let lock = NSLock()
    private var isActive = true
    private var reportsFailures = true

    init(
        onAudio: @escaping @Sendable (CMSampleBuffer) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        self.onAudio = onAudio
        self.onFailure = onFailure
    }

    func deactivate() {
        lock.lock()
        isActive = false
        reportsFailures = false
        lock.unlock()
    }

    func prepareForStop() {
        lock.lock()
        reportsFailures = false
        lock.unlock()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer),
              CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        lock.lock()
        let shouldDeliver = isActive
        lock.unlock()
        if shouldDeliver { onAudio(sampleBuffer) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        let shouldDeliver = isActive && reportsFailures
        reportsFailures = false
        lock.unlock()
        if shouldDeliver { onFailure(SystemAudioCaptureError.from(error).localizedDescription) }
    }
}

nonisolated private enum SystemAudioCaptureError: LocalizedError {
    case permissionDenied
    case noDisplay
    case captureFailure

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String(localized: "Permita o MenuHelp em Ajustes do Sistema > Privacidade e Segurança > Gravação de Tela e Áudio do Sistema e tente novamente.")
        case .noDisplay:
            return String(localized: "Nenhuma tela está disponível para capturar o áudio do computador.")
        case .captureFailure:
            return String(localized: "Não foi possível capturar o áudio do computador. Verifique as permissões e tente novamente.")
        }
    }

    static func from(_ error: Error) -> SystemAudioCaptureError {
        if let captureError = error as? SystemAudioCaptureError { return captureError }
        let cocoaError = error as NSError
        if cocoaError.domain == SCStreamErrorDomain {
            switch cocoaError.code {
            case SCStreamError.Code.userDeclined.rawValue:
                return .permissionDenied
            case SCStreamError.Code.noDisplayList.rawValue,
                 SCStreamError.Code.noCaptureSource.rawValue:
                return .noDisplay
            default:
                break
            }
        }
        return .captureFailure
    }
}
