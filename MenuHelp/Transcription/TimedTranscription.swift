import Foundation

nonisolated struct TimedTranscriptionSegment: Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

/// Every snapshot contains all preceding segments, including completed recognition tasks.
nonisolated struct SpeechTranscriptionSnapshot: Sendable {
    let segments: [TimedTranscriptionSegment]

    var text: String {
        segments.map(\.text).joined(separator: "\n\n")
    }

    var historyText: String {
        segments.map { segment in
            let start = TranscriptionHistoryDocument.durationLabel(segment.startTime)
            let end = TranscriptionHistoryDocument.durationLabel(max(segment.startTime, segment.endTime))
            return "[\(start) – \(end)] \(segment.text)"
        }.joined(separator: "\n\n")
    }
}

nonisolated struct TranscriptionHistoryDocument {
    let startedAt: Date
    let stoppedAt: Date?
    let elapsedTime: TimeInterval
    let snapshot: SpeechTranscriptionSnapshot

    var text: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss XXX"
        let start = String(
            format: String(localized: "Início: %@"),
            formatter.string(from: startedAt)
        )
        let end: String
        if let stoppedAt {
            end = String(format: String(localized: "Fim: %@"), formatter.string(from: stoppedAt))
        } else {
            end = String(
                format: String(localized: "Em andamento até: %@"),
                formatter.string(from: startedAt.addingTimeInterval(elapsedTime))
            )
        }
        let duration = String(
            format: String(localized: "Duração: %@"),
            Self.durationLabel(elapsedTime)
        )
        let content = snapshot.segments.isEmpty
            ? String(localized: "Ainda não há fala reconhecida.")
            : snapshot.historyText
        return [String(localized: "Histórico da transcrição"), start, end, duration, "", content]
            .joined(separator: "\n")
    }

    static func durationLabel(_ interval: TimeInterval) -> String {
        let bounded = interval.isFinite ? min(max(0, interval), Double(Int.max / 2)) : 0
        let seconds = Int(bounded)
        return String(format: "%02ld:%02ld:%02ld", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }
}
