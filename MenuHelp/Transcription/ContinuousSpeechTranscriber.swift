import AudioToolbox
@preconcurrency import AVFAudio
import CoreMedia
import Foundation
@preconcurrency import Speech

/// The conversation model runs for the entire capture. Only finalized phrases
/// enter the history, so later speech cannot rewrite an earlier passage.
@available(macOS 26.0, *)
nonisolated final class ContinuousSpeechTranscriber: @unchecked Sendable {
    private struct RetainedAudio: @unchecked Sendable {
        let buffer: CMSampleBuffer
    }

    private struct InputPacket: Sendable {
        let input: AnalyzerInput
        let reservedDuration: TimeInterval
    }

    /// Account for retained capture samples and queued analyzer input together.
    /// The otherwise unbounded stream therefore never retains unlimited audio.
    private final class AudioBudget: @unchecked Sendable {
        enum Admission { case accepted, closed, overflow }
        private let lock = NSLock()
        private var duration: TimeInterval = 0
        private var count = 0
        private var closed = false

        func reserve(_ seconds: TimeInterval) -> Admission {
            lock.lock()
            defer { lock.unlock() }
            guard !closed else { return .closed }
            guard duration + seconds <= 12, count < 2_000 else {
                closed = true
                return .overflow
            }
            duration += seconds
            count += 1
            return .accepted
        }

        func release(_ seconds: TimeInterval) {
            guard seconds > 0 else { return }
            lock.lock()
            duration = max(0, duration - seconds)
            count = max(0, count - 1)
            lock.unlock()
        }

        func close() {
            lock.lock()
            closed = true
            lock.unlock()
        }
    }

    private struct InputSequence: AsyncSequence, Sendable {
        typealias Element = AnalyzerInput
        let stream: AsyncStream<InputPacket>
        let budget: AudioBudget

        struct AsyncIterator: AsyncIteratorProtocol {
            var iterator: AsyncStream<InputPacket>.AsyncIterator
            let budget: AudioBudget

            mutating func next() async -> AnalyzerInput? {
                guard let packet = await iterator.next() else { return nil }
                budget.release(packet.reservedDuration)
                return packet.input
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(iterator: stream.makeAsyncIterator(), budget: budget)
        }
    }

    /// AVAudioConverter calls its input block synchronously on the speech queue.
    private final class ConverterSource: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer?
        let isEnd: Bool
        private var delivered = false

        init(buffer: AVAudioPCMBuffer?, isEnd: Bool) {
            self.buffer = buffer
            self.isEnd = isEnd
        }

        func provide(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            if let buffer, !delivered {
                delivered = true
                status.pointee = .haveData
                return buffer
            }
            status.pointee = isEnd ? .endOfStream : .noDataNow
            return nil
        }
    }

    /// A new session must await a previous session's asset release before
    /// reserving the same locale, even when finish returns during cleanup.
    private final class ModelReleases: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [String: Task<Void, Never>] = [:]

        private func pendingRelease(for locale: Locale) -> Task<Void, Never>? {
            lock.lock()
            defer { lock.unlock() }
            return pending[locale.identifier]
        }

        func wait(for locale: Locale) async {
            await pendingRelease(for: locale)?.value
        }

        func release(_ locale: Locale) {
            lock.lock()
            let previous = pending[locale.identifier]
            pending[locale.identifier] = Task {
                await previous?.value
                await AssetInventory.release(reservedLocale: locale)
            }
            lock.unlock()
        }
    }

    private static let modelReleases = ModelReleases()

    private let queue = DispatchQueue(label: "com.menuhelp.transcription.continuous", qos: .userInitiated)
    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let analyzerFormat: AVAudioFormat
    private let input: AsyncStream<InputPacket>.Continuation
    private let budget: AudioBudget
    private let reservedLocale: Locale?
    private let onTranscript: @Sendable (SpeechTranscriptionSnapshot) -> Void
    private let onAudioLevel: @Sendable (Double) -> Void
    private let onFailure: @Sendable (String) -> Void

    private var resultsTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var finishTimeout: DispatchWorkItem?
    private var converter: AVAudioConverter?
    private var converterOutputTime: TimeInterval = 0
    private var converterInputEndTime: TimeInterval?
    private var recordingReferencePresentationTime: TimeInterval?
    private var firstPresentationTime: TimeInterval?
    private var lastPresentationTime: TimeInterval?
    private var capturedEndTime: TimeInterval = 0
    private var lastMeterTime: TimeInterval = 0
    private var segments: [TimedTranscriptionSegment] = []
    private var finishRequested = false
    private var completedSnapshot: SpeechTranscriptionSnapshot?
    private var lastFailureMessage: String?
    private var finishWaiters: [CheckedContinuation<SpeechTranscriptionSnapshot, Never>] = []

    static func supports(locale: Locale) async -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        return await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil
    }

    static func make(
        locale: Locale,
        onTranscript: @escaping @Sendable (SpeechTranscriptionSnapshot) -> Void,
        onAudioLevel: @escaping @Sendable (Double) -> Void,
        onFailure: @escaping @Sendable (String) -> Void,
        onPreparation: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> ContinuousSpeechTranscriber {
        guard SpeechTranscriber.isAvailable,
              let selectedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw ContinuousTranscriptionError.unsupportedLanguage
        }
        try Task.checkCancellation()
        let transcriber = SpeechTranscriber(
            locale: selectedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        var ownsReservation = false
        var preparedAnalyzer: SpeechAnalyzer?
        do {
            await modelReleases.wait(for: selectedLocale)
            try Task.checkCancellation()
            ownsReservation = try await AssetInventory.reserve(locale: selectedLocale)
            try Task.checkCancellation()
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                onPreparation(String(localized: "Preparando o modelo de transcrição local…"))
                try await withTaskCancellationHandler {
                    try await installation.downloadAndInstall()
                } onCancel: {
                    installation.progress.cancel()
                }
            }
            try Task.checkCancellation()
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw ContinuousTranscriptionError.modelPreparationFailed
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw ContinuousTranscriptionError.audioFormatUnavailable
            }
            onPreparation(String(localized: "Preparando captura…"))
            let analyzer = SpeechAnalyzer(
                modules: [transcriber],
                options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)
            )
            preparedAnalyzer = analyzer
            try await analyzer.prepareToAnalyze(in: format)
            try Task.checkCancellation()
            let budget = AudioBudget()
            let (stream, continuation) = AsyncStream.makeStream(of: InputPacket.self)
            try await analyzer.start(inputSequence: InputSequence(stream: stream, budget: budget))
            try Task.checkCancellation()
            let engine = ContinuousSpeechTranscriber(
                analyzer: analyzer,
                transcriber: transcriber,
                format: format,
                input: continuation,
                budget: budget,
                reservedLocale: ownsReservation ? selectedLocale : nil,
                onTranscript: onTranscript,
                onAudioLevel: onAudioLevel,
                onFailure: onFailure
            )
            engine.startResults()
            return engine
        } catch {
            if let preparedAnalyzer { await preparedAnalyzer.cancelAndFinishNow() }
            if ownsReservation { await AssetInventory.release(reservedLocale: selectedLocale) }
            if Task.isCancelled { throw CancellationError() }
            if error is CancellationError || error is ContinuousTranscriptionError { throw error }
            throw ContinuousTranscriptionError.modelPreparationFailed
        }
    }

    private init(
        analyzer: SpeechAnalyzer,
        transcriber: SpeechTranscriber,
        format: AVAudioFormat,
        input: AsyncStream<InputPacket>.Continuation,
        budget: AudioBudget,
        reservedLocale: Locale?,
        onTranscript: @escaping @Sendable (SpeechTranscriptionSnapshot) -> Void,
        onAudioLevel: @escaping @Sendable (Double) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        self.analyzer = analyzer
        self.transcriber = transcriber
        analyzerFormat = format
        self.input = input
        self.budget = budget
        self.reservedLocale = reservedLocale
        self.onTranscript = onTranscript
        self.onAudioLevel = onAudioLevel
        self.onFailure = onFailure
    }

    deinit {
        guard completedSnapshot == nil else { return }
        budget.close()
        input.finish()
        resultsTask?.cancel()
        Task { [analyzer] in await analyzer.cancelAndFinishNow() }
        if let reservedLocale { Self.modelReleases.release(reservedLocale) }
    }

    private func startResults() {
        let transcriber = transcriber
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    // Volatile reporting is disabled: each phrase is delivered
                    // once in its final form. No final-result filtering needed.
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    let start = CMTimeGetSeconds(result.range.start)
                    let end = CMTimeGetSeconds(CMTimeRangeGetEnd(result.range))
                    self?.queue.async { [weak self] in self?.receive(text: text, start: start, end: end) }
                }
                self?.queue.async { [weak self] in
                    guard let self, !self.finishRequested else { return }
                    self.fail(.recognitionFailed)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.queue.async { [weak self] in self?.fail(.recognitionFailed) }
            }
        }
    }

    func beginRecording(at presentationTime: CMTime) {
        let seconds = CMTimeGetSeconds(presentationTime)
        queue.async { [self] in
            guard firstPresentationTime == nil, capturedEndTime == 0, seconds.isFinite else { return }
            recordingReferencePresentationTime = seconds
        }
    }

    func consume(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer),
              CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              CMFormatDescriptionGetMediaType(format) == kCMMediaType_Audio,
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return }
        let rate = description.pointee.mSampleRate
        guard rate.isFinite, rate > 0 else { return }
        let duration = Double(CMSampleBufferGetNumSamples(sampleBuffer)) / rate
        guard duration.isFinite, duration > 0 else { return }
        switch budget.reserve(duration) {
        case .closed: return
        case .overflow:
            queue.async { [self] in fail(.audioBacklog) }
            return
        case .accepted: break
        }
        let retained = RetainedAudio(buffer: sampleBuffer)
        queue.async { [self] in
            guard !finishRequested, completedSnapshot == nil else {
                budget.release(duration)
                return
            }
            do {
                let pcm = try Self.copyPCM(from: retained.buffer)
                publishMeter(pcm)
                let offset = captureOffset(for: retained.buffer, duration: duration)
                try convert(pcm, offset: offset, reservedDuration: duration)
            } catch {
                budget.release(duration)
                fail(.audioFormatUnavailable)
            }
        }
    }

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
                budget.close()
                if capturedEndTime == 0 {
                    // No capture samples means no pending recognition to drain.
                    resultsTask?.cancel()
                    Task { [analyzer] in await analyzer.cancelAndFinishNow() }
                    complete()
                    return
                }
                do { try flushConverter() } catch { fail(.audioFormatUnavailable); return }
                input.finish()
                let timeout = DispatchWorkItem { [weak self] in self?.fail(.finalizationTimeout) }
                finishTimeout = timeout
                queue.asyncAfter(deadline: .now() + 20, execute: timeout)
                let resultsTask = resultsTask
                finishTask = Task { [self] in
                    do {
                        try await analyzer.finalizeAndFinishThroughEndOfInput()
                        await resultsTask?.value
                        queue.async { [self] in complete() }
                    } catch {
                        guard !Task.isCancelled else { return }
                        queue.async { [self] in fail(.recognitionFailed) }
                    }
                }
            }
        }
    }

    func failureMessage() async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: lastFailureMessage) }
        }
    }

    private static func copyPCM(from sample: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            throw ContinuousTranscriptionError.audioFormatUnavailable
        }
        var asbd = pointer.pointee
        let count = CMSampleBufferGetNumSamples(sample)
        guard asbd.mFormatID == kAudioFormatLinearPCM, count > 0, count <= Int(UInt32.max),
              let format = AVAudioFormat(streamDescription: &asbd),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
            throw ContinuousTranscriptionError.audioFormatUnavailable
        }
        pcm.frameLength = AVAudioFrameCount(count)
        try sample.withAudioBufferList(flags: .audioBufferListAssure16ByteAlignment) { source, _ in
            let destination = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
            guard source.count == destination.count else { throw ContinuousTranscriptionError.audioFormatUnavailable }
            for index in 0..<source.count {
                guard let src = source[index].mData, let dst = destination[index].mData,
                      source[index].mDataByteSize == destination[index].mDataByteSize else {
                    throw ContinuousTranscriptionError.audioFormatUnavailable
                }
                memcpy(dst, src, Int(source[index].mDataByteSize))
            }
        }
        return pcm
    }

    private func convert(_ pcm: AVAudioPCMBuffer, offset: TimeInterval, reservedDuration: TimeInterval) throws {
        if let converter, converter.inputFormat != pcm.format ||
            abs(offset - (converterInputEndTime ?? offset)) > 0.003 {
            // Finalize the previous converter before a real capture interruption
            // so delayed resampler frames retain their original time position.
            try flushConverter()
            self.converter = nil
        }
        if pcm.format == analyzerFormat {
            yield(pcm, start: offset, reservedDuration: reservedDuration)
            converterInputEndTime = offset + Double(pcm.frameLength) / pcm.format.sampleRate
            return
        }
        if converter == nil {
            guard let converter = AVAudioConverter(from: pcm.format, to: analyzerFormat) else {
                throw ContinuousTranscriptionError.audioFormatUnavailable
            }
            converter.primeMethod = .none
            self.converter = converter
            converterOutputTime = offset
        }
        converterInputEndTime = offset + Double(pcm.frameLength) / pcm.format.sampleRate
        try performConversion(source: ConverterSource(buffer: pcm, isEnd: false), reservedDuration: reservedDuration)
    }

    private func flushConverter() throws {
        guard converter != nil else { return }
        try performConversion(source: ConverterSource(buffer: nil, isEnd: true), reservedDuration: 0)
    }

    private func performConversion(source: ConverterSource, reservedDuration: TimeInterval) throws {
        guard let converter else { return }
        let sourceFrames = Double(source.buffer?.frameLength ?? 0)
        let ratio = analyzerFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = max(1_024, Int(ceil(sourceFrames * ratio)) + 256)
        guard capacity <= Int(UInt32.max) else { throw ContinuousTranscriptionError.audioFormatUnavailable }
        var reservation = reservedDuration
        var outputs: [AVAudioPCMBuffer] = []
        // The source is supplied once. Further calls drain output already held
        // inside the continuous resampler instead of submitting the audio twice.
        for _ in 0..<32 {
            guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: AVAudioFrameCount(capacity)) else {
                throw ContinuousTranscriptionError.audioFormatUnavailable
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, status in source.provide(status) }
            guard error == nil, status != .error else { throw ContinuousTranscriptionError.audioFormatUnavailable }
            if output.frameLength > 0 { outputs.append(output) }
            if status == .inputRanDry || status == .endOfStream {
                // Publish only after the whole conversion succeeds. If it fails,
                // the caller releases the still-owned capture reservation once.
                for output in outputs {
                    yield(output, start: converterOutputTime, reservedDuration: reservation)
                    reservation = 0
                    converterOutputTime += Double(output.frameLength) / analyzerFormat.sampleRate
                }
                budget.release(reservation)
                return
            }
        }
        throw ContinuousTranscriptionError.audioFormatUnavailable
    }

    private func yield(_ pcm: AVAudioPCMBuffer, start: TimeInterval, reservedDuration: TimeInterval) {
        let packet = InputPacket(
            input: AnalyzerInput(buffer: pcm, bufferStartTime: CMTime(seconds: start, preferredTimescale: 1_000_000)),
            reservedDuration: reservedDuration
        )
        switch input.yield(packet) {
        case .enqueued: break
        case .terminated: budget.release(reservedDuration)
        case .dropped:
            budget.release(reservedDuration)
            fail(.audioBacklog)
        @unknown default:
            budget.release(reservedDuration)
            fail(.audioBacklog)
        }
    }

    private func captureOffset(for buffer: CMSampleBuffer, duration: TimeInterval) -> TimeInterval {
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
        var offset = capturedEndTime
        if timestamp.isFinite {
            if firstPresentationTime == nil {
                if let reference = recordingReferencePresentationTime,
                   timestamp - reference >= -0.25, timestamp - reference < 86_400 {
                    firstPresentationTime = reference
                } else {
                    firstPresentationTime = timestamp - capturedEndTime
                }
            }
            if let origin = firstPresentationTime, timestamp > (lastPresentationTime ?? -.infinity) {
                offset = max(capturedEndTime, timestamp - origin)
                lastPresentationTime = timestamp
            }
        }
        capturedEndTime = offset + duration
        return offset
    }

    private func receive(text: String, start: TimeInterval, end: TimeInterval) {
        guard completedSnapshot == nil, !text.isEmpty, start.isFinite, end.isFinite,
              start >= 0, end >= start else { return }
        let boundedStart = max(segments.last?.startTime ?? 0, min(start, capturedEndTime))
        let boundedEnd = max(boundedStart, min(end, capturedEndTime))
        segments.append(TimedTranscriptionSegment(startTime: boundedStart, endTime: boundedEnd, text: text))
        onTranscript(SpeechTranscriptionSnapshot(segments: segments))
    }

    private func publishMeter(_ pcm: AVAudioPCMBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMeterTime >= 0.1 else { return }
        lastMeterTime = now
        guard let samples = pcm.floatChannelData?[0], pcm.frameLength > 0 else { onAudioLevel(0); return }
        var squareSum = 0.0
        var peak = 0.0
        for index in 0..<Int(pcm.frameLength) {
            let value = Double(samples[index])
            guard value.isFinite else { continue }
            let amplitude = min(1, abs(value))
            squareSum += amplitude * amplitude
            peak = max(peak, amplitude)
        }
        let rms = sqrt(squareSum / Double(pcm.frameLength))
        let decibels = 20 * log10(max(max(rms, peak * 0.25), 0.001))
        onAudioLevel(min(1, max(0, (decibels + 60) / 60)))
    }

    private func fail(_ error: ContinuousTranscriptionError) {
        guard completedSnapshot == nil else { return }
        lastFailureMessage = error.localizedDescription
        finishTask?.cancel()
        resultsTask?.cancel()
        Task { [analyzer] in await analyzer.cancelAndFinishNow() }
        complete()
        onFailure(error.localizedDescription)
    }

    private func complete() {
        guard completedSnapshot == nil else { return }
        budget.close()
        input.finish()
        finishRequested = true
        finishTimeout?.cancel()
        finishTimeout = nil
        let snapshot = SpeechTranscriptionSnapshot(segments: segments)
        completedSnapshot = snapshot
        onAudioLevel(0)
        if let reservedLocale { Self.modelReleases.release(reservedLocale) }
        let waiters = finishWaiters
        finishWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: snapshot) }
    }
}

@available(macOS 26.0, *)
nonisolated private enum ContinuousTranscriptionError: LocalizedError {
    case unsupportedLanguage
    case modelPreparationFailed
    case audioFormatUnavailable
    case audioBacklog
    case finalizationTimeout
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage:
            return String(localized: "O modelo de transcrição contínua não está disponível para este idioma neste Mac.")
        case .modelPreparationFailed:
            return String(localized: "Não foi possível preparar o modelo de transcrição local. Verifique a conexão com a internet para baixar o modelo e tente novamente.")
        case .audioFormatUnavailable:
            return String(localized: "Não foi possível preparar o áudio para a transcrição. O texto já reconhecido foi preservado.")
        case .audioBacklog:
            return String(localized: "A transcrição não conseguiu acompanhar o áudio e foi interrompida. O texto já reconhecido foi preservado.")
        case .finalizationTimeout:
            return String(localized: "O reconhecimento de fala demorou demais para finalizar. O texto já reconhecido foi preservado.")
        case .recognitionFailed:
            return String(localized: "O reconhecimento de fala foi interrompido. O texto já reconhecido foi preservado; tente iniciar outra transcrição.")
        }
    }
}
