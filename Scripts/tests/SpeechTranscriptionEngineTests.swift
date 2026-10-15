import AudioToolbox
import CoreMedia
import Foundation

nonisolated enum MockMode: Sendable {
    case normal, noSpeechFirst, fatalFirst, neverFinishes
}

nonisolated final class MockRecorder: @unchecked Sendable {
    static let shared = MockRecorder()
    private let lock = NSLock()
    private var mode: MockMode = .normal
    private var starts = 0
    private var active = 0
    private var overlaps = 0
    private var durations: [Double] = []
    private var failures: [String] = []
    private var levels: [Double] = []

    func reset(_ mode: MockMode) {
        lock.lock()
        self.mode = mode
        starts = 0
        active = 0
        overlaps = 0
        durations = []
        failures = []
        levels = []
        lock.unlock()
    }

    func starting() -> (Int, MockMode) {
        lock.lock()
        defer { lock.unlock() }
        if active > 0 { overlaps += 1 }
        active += 1
        starts += 1
        return (starts, mode)
    }

    func ended(duration: Double) {
        lock.lock()
        active -= 1
        durations.append(duration)
        lock.unlock()
    }

    func failure(_ message: String) {
        lock.lock()
        failures.append(message)
        lock.unlock()
    }

    func level(_ value: Double) {
        lock.lock()
        levels.append(value)
        lock.unlock()
    }

    func snapshot() -> (starts: Int, active: Int, overlaps: Int, durations: [Double], failures: [String], levels: [Double]) {
        lock.lock()
        defer { lock.unlock() }
        return (starts, active, overlaps, durations, failures, levels)
    }
}

nonisolated enum SFSpeechRecognizerAuthorizationStatus {
    case authorized
}
nonisolated enum SFSpeechRecognitionTaskHint {
    case unspecified
    case dictation
}
nonisolated enum SFSpeechRecognitionTaskState {
    case starting, running, finishing, completed
}
nonisolated struct SFSpeechTranscriptionSegment: Sendable {
    let timestamp: TimeInterval
    let duration: TimeInterval
    let substring: String
    let substringRange: NSRange
}
nonisolated struct SFTranscription: Sendable {
    let formattedString: String

    var segments: [SFSpeechTranscriptionSegment] {
        [SFSpeechTranscriptionSegment(
            timestamp: 0,
            duration: 1,
            substring: formattedString,
            substringRange: NSRange(location: 0, length: (formattedString as NSString).length)
        )]
    }
}
nonisolated struct SFSpeechRecognitionResult: Sendable {
    let bestTranscription: SFTranscription
    let isFinal: Bool
}
nonisolated final class SFSpeechAudioBufferRecognitionRequest {
    var requiresOnDeviceRecognition = false
    var shouldReportPartialResults = false
    var addsPunctuation = false
    var taskHint = SFSpeechRecognitionTaskHint.dictation
    weak var task: SFSpeechRecognitionTask?
    func appendAudioSampleBuffer(_ buffer: CMSampleBuffer) { task?.append(buffer) }
    func endAudio() {}
}

nonisolated final class SFSpeechRecognizer {
    var supportsOnDeviceRecognition = true
    var isAvailable = true
    var queue = OperationQueue()
    static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus { .authorized }
    static func supportedLocales() -> Set<Locale> { [Locale(identifier: "pt_BR")] }
    init?(locale: Locale) {}
    func recognitionTask(
        with request: SFSpeechAudioBufferRecognitionRequest,
        resultHandler: @escaping @Sendable (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> SFSpeechRecognitionTask {
        precondition(request.requiresOnDeviceRecognition)
        precondition(request.shouldReportPartialResults && !request.addsPunctuation)
        precondition(request.taskHint == .unspecified)
        let task = SFSpeechRecognitionTask(handler: resultHandler)
        request.task = task
        return task
    }
}

nonisolated final class SFSpeechRecognitionTask: @unchecked Sendable {
    private let lock = NSLock()
    private var taskState = SFSpeechRecognitionTaskState.starting
    private var audioDuration = 0.0
    private let ordinal: Int
    private let mode: MockMode
    private let handler: @Sendable (SFSpeechRecognitionResult?, Error?) -> Void

    var state: SFSpeechRecognitionTaskState {
        lock.lock()
        defer { lock.unlock() }
        return taskState
    }

    init(handler: @escaping @Sendable (SFSpeechRecognitionResult?, Error?) -> Void) {
        (ordinal, mode) = MockRecorder.shared.starting()
        self.handler = handler
    }

    func append(_ buffer: CMSampleBuffer) {
        let format = CMSampleBufferGetFormatDescription(buffer)!
        let rate = CMAudioFormatDescriptionGetStreamBasicDescription(format)!.pointee.mSampleRate
        lock.lock()
        audioDuration += Double(CMSampleBufferGetNumSamples(buffer)) / rate
        taskState = .running
        lock.unlock()
        if mode == .noSpeechFirst && ordinal == 1 { return }
        handler(SFSpeechRecognitionResult(
            bestTranscription: SFTranscription(formattedString: "trecho \(ordinal) parcial"),
            isFinal: false
        ), nil)
        if mode == .fatalFirst && ordinal == 1 {
            handler(nil, NSError(domain: "kLSRErrorDomain", code: 201))
        }
    }

    func finish() {
        lock.lock()
        guard taskState != .completed, taskState != .finishing else { lock.unlock(); return }
        taskState = .finishing
        lock.unlock()
        guard mode != .neverFinishes else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) { [self] in
            if mode == .noSpeechFirst && ordinal == 1 {
                handler(nil, NSError(domain: "kAFAssistantErrorDomain", code: 1110))
            } else {
                handler(SFSpeechRecognitionResult(
                    bestTranscription: SFTranscription(formattedString: "trecho \(ordinal) final"),
                    isFinal: true
                ), nil)
            }
            // Deliberately deliver final text before task completion. The engine
            // must wait here rather than starting an overlapping replacement.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) { [self] in
                markCompleted()
            }
        }
    }

    func cancel() { markCompleted() }

    private func markCompleted() {
        lock.lock()
        guard taskState != .completed else { lock.unlock(); return }
        taskState = .completed
        let duration = audioDuration
        lock.unlock()
        MockRecorder.shared.ended(duration: duration)
    }
}

nonisolated func makeAudio(seconds: Int = 1) -> CMSampleBuffer {
    let sampleCount = seconds * 16_000
    var description = AudioStreamBasicDescription(
        mSampleRate: 16_000,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 4,
        mFramesPerPacket: 1,
        mBytesPerFrame: 4,
        mChannelsPerFrame: 1,
        mBitsPerChannel: 32,
        mReserved: 0
    )
    var format: CMAudioFormatDescription?
    precondition(CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &description,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &format
    ) == noErr)
    var block: CMBlockBuffer?
    precondition(CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: sampleCount * 4,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: sampleCount * 4,
        flags: 0,
        blockBufferOut: &block
    ) == noErr)
    let samples = [Float](repeating: 0.2, count: sampleCount)
    samples.withUnsafeBytes { bytes in
        precondition(CMBlockBufferReplaceDataBytes(
            with: bytes.baseAddress!,
            blockBuffer: block!,
            offsetIntoDestination: 0,
            dataLength: bytes.count
        ) == noErr)
    }
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 16_000),
        presentationTimeStamp: .zero,
        decodeTimeStamp: .invalid
    )
    var sampleSize = 4
    var buffer: CMSampleBuffer?
    precondition(CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: block,
        formatDescription: format,
        sampleCount: sampleCount,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 1,
        sampleSizeArray: &sampleSize,
        sampleBufferOut: &buffer
    ) == noErr)
    return buffer!
}

@main
struct SpeechHarness {
    static func engine() throws -> SpeechTranscriptionEngine {
        try SpeechTranscriptionEngine(
            locale: Locale(identifier: "pt_BR"),
            onTranscript: { _ in },
            onAudioLevel: { MockRecorder.shared.level($0) },
            onFailure: { MockRecorder.shared.failure($0) }
        )
    }

    static func check(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }

    static func main() async throws {
        MockRecorder.shared.reset(.normal)
        let empty = try engine()
        check((await empty.finish()).text == "", "empty session should finish")
        check(MockRecorder.shared.snapshot().starts == 0, "recognition must start lazily")
        print("PASS lazy empty finish")

        MockRecorder.shared.reset(.normal)
        let rotating = try engine()
        let audio = makeAudio()
        for _ in 0..<18 { rotating.consume(audio) }
        async let firstFinish = rotating.finish()
        async let secondFinish = rotating.finish()
        let results = await (firstFinish, secondFinish)
        check(results.0.text == "trecho 1 final\n\ntrecho 2 final", "finish must include buffered audio")
        check(results.0.text == results.1.text, "concurrent finish callers must agree")
        check((await rotating.finish()).text == results.0.text, "finish must be idempotent")
        let rotated = MockRecorder.shared.snapshot()
        check(rotated.starts == 2 && rotated.overlaps == 0 && rotated.active == 0, "tasks must never overlap")
        check(rotated.durations == [11, 7], "rotation must preserve every audio frame")
        check(rotated.levels.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, "meter must remain bounded")
        check(rotated.levels.contains { $0 > 0 }, "float PCM must produce an audio level")
        check(await rotating.failureMessage() == nil, "successful rotation must have no retained failure")
        print("PASS rotation, delayed completion, buffered stop, concurrent/idempotent finish, PCM meter")

        MockRecorder.shared.reset(.noSpeechFirst)
        let silence = try engine()
        for _ in 0..<18 { silence.consume(audio) }
        let afterSilence = await silence.finish()
        check(afterSilence.text == "trecho 2 final", "no-speech task should permit next chunk")
        let silentSnapshot = MockRecorder.shared.snapshot()
        check(silentSnapshot.overlaps == 0 && silentSnapshot.failures.isEmpty, "silence must be nonfatal")
        print("PASS no-speech recovery")

        MockRecorder.shared.reset(.fatalFirst)
        let failed = try engine()
        failed.consume(audio)
        let preserved = await failed.finish()
        check(preserved.text == "trecho 1 parcial", "fatal error must preserve current partial")
        check(await failed.failureMessage() != nil, "failure must remain available after finish")
        check((await failed.finish()).text == preserved.text, "finish after fatal error must not deadlock")
        print("PASS fatal draft preservation, retained failure, finish after fatal")

        MockRecorder.shared.reset(.normal)
        let overloaded = try engine()
        for _ in 0..<62 { overloaded.consume(audio) }
        _ = await overloaded.finish()
        check(await overloaded.failureMessage()?.contains("acompanhar") == true, "bounded backlog must fail visibly")
        check(MockRecorder.shared.snapshot().active == 0, "backlog failure must cancel the active task")
        print("PASS bounded audio backlog")

        MockRecorder.shared.reset(.neverFinishes)
        let timeout = try engine()
        timeout.consume(audio)
        let draft = await timeout.finish()
        check(draft.text == "trecho 1 parcial", "timeout must retain draft")
        check(await timeout.failureMessage()?.contains("demorou") == true, "timeout failure must be retained")
        check((await timeout.finish()).text == draft.text, "timeout must resolve all later finish callers")
        print("PASS real 8-second finalization timeout and continuation resolution")
    }
}
