import AudioToolbox
import CoreMedia
import Foundation
@preconcurrency import Speech

/// All recognition state and Speech calls are confined to `queue`. The owner stops
/// capture before calling finish; callbacks deliver values without touching UI.
nonisolated final class SpeechTranscriptionEngine: @unchecked Sendable {
    /// ScreenCaptureKit audio is read-only here. This wrapper retains the buffer
    /// across the queue hop without claiming all CMSampleBuffers are Sendable.
    private struct RetainedAudio: @unchecked Sendable {
        let buffer: CMSampleBuffer
    }

    private struct PendingAudio {
        let buffer: CMSampleBuffer
        let duration: Double
        let captureOffset: TimeInterval
        let rms: Double?
    }

    private struct AudioEnergy {
        let rms: Double
        let peak: Double
    }

    private struct AudioSpan {
        let recognitionStart: TimeInterval
        var recognitionEnd: TimeInterval
        let captureStart: TimeInterval

        var captureEnd: TimeInterval {
            captureStart + recognitionEnd - recognitionStart
        }
    }

    private struct RecognizedWord: Sendable {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
    }

    private let queue = DispatchQueue(
        label: "com.menuhelp.transcription.speech",
        qos: .userInitiated
    )
    private let recognizer: SFSpeechRecognizer
    private let onTranscript: @Sendable (SpeechTranscriptionSnapshot) -> Void
    private let onAudioLevel: @Sendable (Double) -> Void
    private let onFailure: @Sendable (String) -> Void

    // A task must finish before its replacement starts. Audio arriving during
    // that interval is bounded independently of total recording length.
    private let maximumTaskDuration = 12.0
    private let minimumTaskDuration = 1.5
    private let pauseDuration = 0.65
    private let audibleThreshold = 0.002
    private let maximumPendingDuration = 12.0
    private let drainTimeout = 8.0
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var taskID: UUID?
    private var taskDuration = 0.0
    private var taskContainsAudibleAudio = false
    private var trailingSilenceDuration = 0.0
    private var taskAudioTimeline: [AudioSpan] = []
    private var isDraining = false
    private var receivedTerminalResult = false
    private var drainWorkItem: DispatchWorkItem?
    private var pendingAudio: [PendingAudio] = []
    private var pendingDuration = 0.0

    private var recordingReferencePresentationTime: TimeInterval?
    private var firstPresentationTime: TimeInterval?
    private var lastPresentationTime: TimeInterval?
    private var capturedEndTime: TimeInterval = 0
    private var confirmedSegments: [TimedTranscriptionSegment] = []
    private var partialSegments: [TimedTranscriptionSegment] = []
    private var lastPublishedSegments: [TimedTranscriptionSegment] = []
    private var lastMeterTime = 0.0
    private var finishRequested = false
    private var completedSnapshot: SpeechTranscriptionSnapshot?
    private var lastFailureMessage: String?
    private var finishWaiters: [CheckedContinuation<SpeechTranscriptionSnapshot, Never>] = []

    init(
        locale: Locale,
        onTranscript: @escaping @Sendable (SpeechTranscriptionSnapshot) -> Void,
        onAudioLevel: @escaping @Sendable (Double) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechTranscriptionError.permissionDenied
        }
        guard SFSpeechRecognizer.supportedLocales().contains(locale),
              let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechTranscriptionError.unsupportedLanguage
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw SpeechTranscriptionError.localRecognitionUnavailable
        }
        guard recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }
        self.recognizer = recognizer
        self.onTranscript = onTranscript
        self.onAudioLevel = onAudioLevel
        self.onFailure = onFailure
        let callbackQueue = OperationQueue()
        callbackQueue.name = "com.menuhelp.transcription.speech-results"
        callbackQueue.maxConcurrentOperationCount = 1
        callbackQueue.underlyingQueue = queue
        recognizer.queue = callbackQueue
    }

    /// ScreenCaptureKit timestamps use the host clock. Anchoring immediately
    /// before capture starts also retains silence before the first audio sample.
    func beginRecording(at presentationTime: CMTime) {
        let seconds = CMTimeGetSeconds(presentationTime)
        queue.async { [self] in
            guard firstPresentationTime == nil, capturedEndTime == 0,
                  seconds.isFinite else { return }
            recordingReferencePresentationTime = seconds
        }
    }

    /// Retains the sample until the serial queue consumes it. No PCM pointers
    /// escape the capture callback or the meter's buffer-list scope.
    func consume(_ sampleBuffer: CMSampleBuffer) {
        let retainedAudio = RetainedAudio(buffer: sampleBuffer)
        queue.async { [self] in
            let sampleBuffer = retainedAudio.buffer
            guard !finishRequested, completedSnapshot == nil,
                  sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer),
                  CMSampleBufferGetNumSamples(sampleBuffer) > 0,
                  let format = CMSampleBufferGetFormatDescription(sampleBuffer),
                  CMFormatDescriptionGetMediaType(format) == kCMMediaType_Audio,
                  let audioDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format)
            else { return }

            let sampleRate = audioDescription.pointee.mSampleRate
            guard sampleRate.isFinite, sampleRate > 0 else { return }
            let duration = Double(CMSampleBufferGetNumSamples(sampleBuffer)) / sampleRate
            guard duration.isFinite, duration > 0 else { return }
            let energy = Self.audioEnergy(for: sampleBuffer, description: audioDescription.pointee)
            publishMeter(energy)
            let offset = captureOffset(for: sampleBuffer, duration: duration)

            if taskID == nil { startTask() }
            guard completedSnapshot == nil else { return }
            appendOrBuffer(PendingAudio(
                buffer: sampleBuffer,
                duration: duration,
                captureOffset: offset,
                rms: energy?.rms
            ))
        }
    }

    /// Stops accepting input, transcribes any captured audio awaiting rotation,
    /// and returns the full timed history after the last task drains. Repeated
    /// callers share the same completion, including after an earlier failure.
    func finish() async -> SpeechTranscriptionSnapshot {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if let completedSnapshot {
                    continuation.resume(returning: completedSnapshot)
                    return
                }
                finishWaiters.append(continuation)
                guard !finishRequested else { return }
                finishRequested = true
                if taskID != nil {
                    beginDraining()
                } else if !pendingAudio.isEmpty {
                    startTask()
                    flushPendingAudio()
                } else {
                    complete()
                }
            }
        }
    }

    /// Lets the owner read the retained failure after awaiting finish, without
    /// relying on the delivery order of its main-actor callback tasks.
    func failureMessage() async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: lastFailureMessage)
            }
        }
    }

    private func startTask() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard taskID == nil, completedSnapshot == nil else { return }
        guard recognizer.supportsOnDeviceRecognition else {
            fail(.localRecognitionUnavailable)
            return
        }
        guard recognizer.isAvailable else {
            fail(.recognizerUnavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.taskHint = .unspecified
        let id = UUID()
        self.request = request
        taskID = id
        taskDuration = 0
        taskContainsAudibleAudio = false
        trailingSilenceDuration = 0
        taskAudioTimeline.removeAll(keepingCapacity: true)
        partialSegments = []
        isDraining = false
        receivedTerminalResult = false
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Extract only immutable values before entering the state queue.
            let transcription = result?.bestTranscription
            let text = transcription?.formattedString
            let words = transcription.map(Self.recognizedWords)
            let isFinal = result?.isFinal ?? false
            let recognitionError = error as NSError?
            self?.queue.async { [weak self] in
                self?.receive(words: words, text: text, isFinal: isFinal, error: recognitionError, taskID: id)
            }
        }
    }

    private func appendOrBuffer(_ audio: PendingAudio) {
        guard completedSnapshot == nil else { return }
        if isDraining || taskDuration + audio.duration >= maximumTaskDuration {
            buffer(audio)
            if completedSnapshot == nil { beginDraining() }
        } else {
            recordAudioSpan(audio)
            request?.appendAudioSampleBuffer(audio.buffer)
            taskDuration += audio.duration
            if let rms = audio.rms {
                if rms >= audibleThreshold {
                    taskContainsAudibleAudio = true
                    trailingSilenceDuration = 0
                } else {
                    trailingSilenceDuration += audio.duration
                }
            } else {
                // An unknown PCM layout must not be treated as silence and
                // split an utterance while speech may still be present.
                trailingSilenceDuration = 0
            }
            if taskContainsAudibleAudio,
               taskDuration >= minimumTaskDuration,
               trailingSilenceDuration >= pauseDuration {
                // End at a natural pause. Keep incoming audio in the bounded
                // buffer until this task is fully complete, then send it once.
                beginDraining()
            }
        }
    }

    private func buffer(_ audio: PendingAudio) {
        guard pendingDuration + audio.duration <= maximumPendingDuration,
              pendingAudio.count < 2_000 else {
            // Stop visibly rather than dropping speech while claiming a complete
            // transcript. The current draft remains available for saving.
            fail(.audioBacklog)
            return
        }
        pendingAudio.append(audio)
        pendingDuration += audio.duration
    }

    private func beginDraining() {
        guard let id = taskID, !isDraining, completedSnapshot == nil else { return }
        isDraining = true
        request?.endAudio()
        task?.finish()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.taskID == id, self.isDraining,
                  self.completedSnapshot == nil else { return }
            self.fail(.finalizationTimeout)
        }
        drainWorkItem = timeout
        queue.asyncAfter(deadline: .now() + drainTimeout, execute: timeout)
    }

    private func receive(words: [RecognizedWord]?, text: String?, isFinal: Bool, error: NSError?, taskID id: UUID) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard taskID == id, !receivedTerminalResult, completedSnapshot == nil else { return }
        if let text {
            partialSegments = timedSegments(from: words ?? [], fallbackText: text)
            // Interim hypotheses may rewrite the entire current utterance.
            // Retain them for recovery, but publish only a completed passage.
        }

        // A recognizer sometimes returns its final result and an error together.
        // Keep the result, but still surface genuine failures.
        if let error, !isNoSpeech(error) {
            fail(SpeechTranscriptionError.from(error))
            return
        }
        guard isFinal || error != nil else { return }
        receivedTerminalResult = true
        beginDraining()
        endTaskWhenCompleted(id: id)
    }

    private func endTaskWhenCompleted(id: UUID) {
        guard taskID == id, completedSnapshot == nil else { return }
        if task?.state == .completed {
            endTask()
        } else {
            // A final text callback can precede the underlying task's terminal
            // state. Wait for actual completion so replacements cannot overlap.
            queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.endTaskWhenCompleted(id: id)
            }
        }
    }

    private func endTask() {
        confirmedSegments.append(contentsOf: partialSegments)
        partialSegments = []
        drainWorkItem?.cancel()
        drainWorkItem = nil
        taskID = nil
        request = nil
        task = nil
        taskDuration = 0
        taskContainsAudibleAudio = false
        trailingSilenceDuration = 0
        taskAudioTimeline.removeAll(keepingCapacity: true)
        isDraining = false
        receivedTerminalResult = false
        publishTranscript()

        if !pendingAudio.isEmpty {
            startTask()
            flushPendingAudio()
        } else if finishRequested {
            complete()
        }
    }

    private func flushPendingAudio() {
        guard taskID != nil, completedSnapshot == nil else { return }
        while !pendingAudio.isEmpty, !isDraining, completedSnapshot == nil {
            let audio = pendingAudio.removeFirst()
            pendingDuration = max(0, pendingDuration - audio.duration)
            appendOrBuffer(audio)
        }
        if finishRequested, pendingAudio.isEmpty, !isDraining,
           completedSnapshot == nil {
            beginDraining()
        }
    }

    private func isNoSpeech(_ error: NSError) -> Bool {
        error.domain == "kAFAssistantErrorDomain" && error.code == 1110
    }

    /// Recognition timestamps describe only the samples sent to one Speech
    /// request. Capture timestamps retain elapsed silence and interruptions.
    private func captureOffset(for buffer: CMSampleBuffer, duration: TimeInterval) -> TimeInterval {
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
        var offset = capturedEndTime
        if timestamp.isFinite {
            if firstPresentationTime == nil {
                if let reference = recordingReferencePresentationTime,
                   timestamp - reference >= -0.25,
                   timestamp - reference < 86_400 {
                    firstPresentationTime = reference
                } else {
                    // A different timestamp epoch, or an initial sample without
                    // a timestamp, must not reset an already advancing clock.
                    firstPresentationTime = timestamp - capturedEndTime
                }
            }
            if let origin = firstPresentationTime,
               timestamp > (lastPresentationTime ?? -.infinity) {
                offset = max(capturedEndTime, timestamp - origin)
                lastPresentationTime = timestamp
            }
        }
        capturedEndTime = offset + duration
        return offset
    }

    private func recordAudioSpan(_ audio: PendingAudio) {
        let span = AudioSpan(
            recognitionStart: taskDuration,
            recognitionEnd: taskDuration + audio.duration,
            captureStart: audio.captureOffset
        )
        if let previous = taskAudioTimeline.last,
           abs(previous.captureEnd - audio.captureOffset) <= 0.001 {
            // Most streams are continuous. Retain a new span only when the
            // capture timeline diverges from the concatenated Speech input.
            taskAudioTimeline[taskAudioTimeline.count - 1].recognitionEnd = span.recognitionEnd
        } else {
            taskAudioTimeline.append(span)
        }
    }

    private func captureTime(for recognitionTime: TimeInterval, isEnd: Bool) -> TimeInterval {
        guard let first = taskAudioTimeline.first,
              let last = taskAudioTimeline.last else { return 0 }
        let time = max(0, recognitionTime)
        if time <= first.recognitionStart { return first.captureStart }
        if time >= last.recognitionEnd { return last.captureEnd }

        var lower = 0
        var upper = taskAudioTimeline.count - 1
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let end = taskAudioTimeline[middle].recognitionEnd
            if time < end || (isEnd && time == end) {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        let span = taskAudioTimeline[lower]
        return span.captureStart + min(max(0, time - span.recognitionStart), span.recognitionEnd - span.recognitionStart)
    }

    private static func recognizedWords(_ transcription: SFTranscription) -> [RecognizedWord] {
        let formattedText = transcription.formattedString as NSString
        let segments = transcription.segments
        return segments.enumerated().compactMap { index, segment in
            guard segment.timestamp.isFinite, segment.duration.isFinite,
                  segment.timestamp >= 0, segment.duration >= 0 else { return nil }
            let lower = index == 0 ? 0 : segment.substringRange.location
            let upper = index + 1 < segments.count
                ? segments[index + 1].substringRange.location
                : formattedText.length
            let text: String
            if lower >= 0, lower <= upper, upper <= formattedText.length {
                // Include the spaces and punctuation following each word so a
                // grouped phrase preserves the native formatted transcription.
                text = formattedText.substring(with: NSRange(location: lower, length: upper - lower))
            } else {
                text = segment.substring + " "
            }
            return RecognizedWord(
                startTime: segment.timestamp,
                endTime: segment.timestamp + segment.duration,
                text: text
            )
        }
    }

    private func timedSegments(from words: [RecognizedWord], fallbackText: String) -> [TimedTranscriptionSegment] {
        guard !words.isEmpty else {
            let text = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [TimedTranscriptionSegment(
                startTime: taskAudioTimeline.first?.captureStart ?? 0,
                endTime: taskAudioTimeline.last?.captureEnd ?? 0,
                text: text
            )]
        }

        var phrases: [TimedTranscriptionSegment] = []
        var phraseStart: TimeInterval?
        var phraseEnd: TimeInterval = 0
        var phraseText = ""
        for word in words {
            let start = captureTime(for: word.startTime, isEnd: false)
            let end = max(start, captureTime(for: word.endTime, isEnd: true))
            if let previousStart = phraseStart,
               start - phraseEnd >= 1 || end - previousStart > 10 {
                let text = phraseText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    phrases.append(TimedTranscriptionSegment(startTime: previousStart, endTime: phraseEnd, text: text))
                }
                phraseStart = start
                phraseText = word.text
                phraseEnd = end
            } else {
                if phraseStart == nil { phraseStart = start }
                phraseText += word.text
                phraseEnd = max(phraseEnd, end)
            }
        }
        let text = phraseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let phraseStart, !text.isEmpty {
            phrases.append(TimedTranscriptionSegment(startTime: phraseStart, endTime: phraseEnd, text: text))
        }
        return phrases
    }

    private func snapshot() -> SpeechTranscriptionSnapshot {
        SpeechTranscriptionSnapshot(segments: confirmedSegments)
    }

    private func publishTranscript() {
        let value = snapshot()
        guard value.segments.count != lastPublishedSegments.count ||
                zip(value.segments, lastPublishedSegments).contains(where: {
                    $0.0.startTime != $0.1.startTime || $0.0.endTime != $0.1.endTime || $0.0.text != $0.1.text
                }) else { return }
        lastPublishedSegments = value.segments
        onTranscript(value)
    }

    private func fail(_ error: SpeechTranscriptionError) {
        guard completedSnapshot == nil else { return }
        let message = error.localizedDescription
        lastFailureMessage = message
        // Invalidate the callback ID before cancellation produces another callback.
        taskID = nil
        task?.cancel()
        task = nil
        request = nil
        // Recovery must still preserve the latest recognized words when the
        // recognizer cannot deliver a final result. Earlier passages stay fixed.
        confirmedSegments.append(contentsOf: partialSegments)
        partialSegments = []
        publishTranscript()
        complete()
        onFailure(message)
    }

    private func complete() {
        guard completedSnapshot == nil else { return }
        let value = snapshot()
        completedSnapshot = value
        finishRequested = true
        drainWorkItem?.cancel()
        drainWorkItem = nil
        pendingAudio.removeAll()
        pendingDuration = 0
        onAudioLevel(0)
        let waiters = finishWaiters
        finishWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: value) }
    }

    private func publishMeter(_ energy: AudioEnergy?) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMeterTime >= 0.1 else { return }
        lastMeterTime = now
        guard let energy else {
            onAudioLevel(0)
            return
        }
        let amplitude = max(energy.rms, energy.peak * 0.25)
        let decibels = 20 * log10(max(amplitude, 0.001))
        onAudioLevel(min(1, max(0, (decibels + 60) / 60)))
    }

    private static func audioEnergy(
        for buffer: CMSampleBuffer,
        description: AudioStreamBasicDescription
    ) -> AudioEnergy? {
        guard description.mFormatID == kAudioFormatLinearPCM,
              description.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              description.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              description.mBitsPerChannel == 32,
              description.mChannelsPerFrame == 1 else {
            return nil
        }

        return try? buffer.withAudioBufferList(
            flags: .audioBufferListAssure16ByteAlignment
        ) { list, _ -> AudioEnergy? in
            var squareSum = 0.0
            var peak = 0.0
            var sampleCount = 0
            for audioBuffer in list {
                guard audioBuffer.mNumberChannels == 1, let data = audioBuffer.mData else { continue }
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.stride
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<count {
                    let value = Double(samples[index])
                    guard value.isFinite else { continue }
                    let amplitude = min(1, abs(value))
                    squareSum += amplitude * amplitude
                    peak = max(peak, amplitude)
                    sampleCount += 1
                }
            }
            guard sampleCount > 0 else { return nil }
            return AudioEnergy(rms: sqrt(squareSum / Double(sampleCount)), peak: peak)
        }
    }
}

nonisolated private enum SpeechTranscriptionError: LocalizedError {
    case permissionDenied
    case unsupportedLanguage
    case localRecognitionUnavailable
    case recognizerUnavailable
    case missingModels
    case dictationDisabled
    case audioBacklog
    case finalizationTimeout
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String(localized: "Permita o MenuHelp em Ajustes do Sistema > Privacidade e Segurança > Reconhecimento de Fala e tente novamente.")
        case .unsupportedLanguage:
            return String(localized: "O reconhecimento de fala não oferece suporte ao idioma selecionado neste Mac.")
        case .localRecognitionUnavailable:
            return String(localized: "A transcrição local não está disponível para este idioma neste Mac. Ative o Ditado nesse idioma em Ajustes do Sistema > Teclado e tente novamente.")
        case .recognizerUnavailable:
            return String(localized: "O reconhecimento de fala está indisponível neste momento. Verifique o Ditado em Ajustes do Sistema > Teclado e tente novamente.")
        case .missingModels:
            return String(localized: "O modelo de fala deste idioma não está instalado. Ative o Ditado nesse idioma em Ajustes do Sistema > Teclado, aguarde a instalação e tente novamente.")
        case .dictationDisabled:
            return String(localized: "Ative o Ditado em Ajustes do Sistema > Teclado para usar a transcrição local.")
        case .audioBacklog:
            return String(localized: "A transcrição não conseguiu acompanhar o áudio e foi interrompida. O texto já reconhecido foi preservado.")
        case .finalizationTimeout:
            return String(localized: "O reconhecimento de fala demorou demais para finalizar. O texto já reconhecido foi preservado.")
        case .recognitionFailed:
            return String(localized: "O reconhecimento de fala foi interrompido. O texto já reconhecido foi preservado; tente iniciar outra transcrição.")
        }
    }

    static func from(_ error: NSError) -> SpeechTranscriptionError {
        switch (error.domain, error.code) {
        case ("kLSRErrorDomain", 102): return .missingModels
        case ("kLSRErrorDomain", 201): return .dictationDisabled
        case ("kAFAssistantErrorDomain", 1700): return .permissionDenied
        default: return .recognitionFailed
        }
    }
}
