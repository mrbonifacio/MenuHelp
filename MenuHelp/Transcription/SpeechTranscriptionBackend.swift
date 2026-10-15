import CoreMedia
import Foundation

nonisolated protocol SpeechTranscriptionBackend: Sendable {
    func beginRecording(at presentationTime: CMTime)
    func consume(_ sampleBuffer: CMSampleBuffer)
    func finish() async -> SpeechTranscriptionSnapshot
    func failureMessage() async -> String?
}

extension SpeechTranscriptionEngine: SpeechTranscriptionBackend {
    static func make(
        locale: Locale,
        onTranscript: @escaping @Sendable (SpeechTranscriptionSnapshot) -> Void,
        onAudioLevel: @escaping @Sendable (Double) -> Void,
        onFailure: @escaping @Sendable (String) -> Void,
        onPreparation: @escaping @Sendable (String) -> Void
    ) async throws -> any SpeechTranscriptionBackend {
        if #available(macOS 26.0, *), await ContinuousSpeechTranscriber.supports(locale: locale) {
            return try await ContinuousSpeechTranscriber.make(
                locale: locale,
                onTranscript: onTranscript,
                onAudioLevel: onAudioLevel,
                onFailure: onFailure,
                onPreparation: onPreparation
            )
        }

        onPreparation(String(localized: "Preparando captura…"))
        return try SpeechTranscriptionEngine(
            locale: locale,
            onTranscript: onTranscript,
            onAudioLevel: onAudioLevel,
            onFailure: onFailure
        )
    }
}

@available(macOS 26.0, *)
extension ContinuousSpeechTranscriber: SpeechTranscriptionBackend {}
