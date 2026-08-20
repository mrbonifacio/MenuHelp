//
//  BrightnessService.swift
//  MenuHelp
//

import Combine
import CoreGraphics
import Foundation

class DisplayInfo: ObservableObject, Identifiable {
    let id: Int
    let name: String
    let maximumRawBrightness: Int

    @Published var brightness: Double

    init(id: Int, name: String, currentBrightness: Int, maximumBrightness: Int) {
        self.id = id
        self.name = name
        self.maximumRawBrightness = Swift.max(maximumBrightness, 1)
        self.brightness = Self.percentage(
            current: currentBrightness,
            maximum: self.maximumRawBrightness
        )
    }

    func updatePreview(_ value: Double) {
        brightness = Swift.min(Swift.max(value, 0), 100)
    }

    func commitBrightness() {
        BrightnessService.shared.setDisplayBrightness(
            displayId: id,
            percentage: brightness,
            maximumRawBrightness: maximumRawBrightness
        )
    }

    func updateFromReading(current: Int, maximum: Int) {
        brightness = Self.percentage(current: current, maximum: maximum)
    }

    private static func percentage(current: Int, maximum: Int) -> Double {
        guard maximum > 0 else { return 0 }
        let value = (Double(current) / Double(maximum)) * 100
        return Swift.min(Swift.max(value, 0), 100)
    }
}

class BrightnessService: ObservableObject {
    static let shared = BrightnessService()

    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var backendAvailable = false
    @Published private(set) var backendName: String?
    @Published private(set) var detectedExternalDisplayCount = 0
    @Published private(set) var errorMessage: String?

    private var backend: BrightnessBackend?

    /// PATH que apps GUI normalmente não recebem do shell do usuário.
    private static let homebrewPath = "/opt/homebrew/bin:/usr/local/bin"
    private static let m1ddcPaths = [
        "/opt/homebrew/bin/m1ddc",
        "/usr/local/bin/m1ddc",
    ]
    private static let ddcctlPaths = [
        "/opt/homebrew/bin/ddcctl",
        "/usr/local/bin/ddcctl",
    ]

    private init() {}

    func checkBackendAvailability() {
        let m1ddcPath = locateCommand(possiblePaths: Self.m1ddcPaths)
        let ddcctlPath = locateCommand(possiblePaths: Self.ddcctlPaths)

#if arch(arm64)
        backend = m1ddcPath.map(BrightnessBackend.m1ddc)
            ?? ddcctlPath.map(BrightnessBackend.ddcctl)
#else
        backend = ddcctlPath.map(BrightnessBackend.ddcctl)
#endif

        backendAvailable = backend != nil
        backendName = backend?.name
        refreshDisplays()
    }

    func refreshDisplays() {
        detectedExternalDisplayCount = onlineExternalDisplayCount() ?? 0
        displays = []
        errorMessage = nil

        guard let backend else { return }
        guard detectedExternalDisplayCount > 0 else { return }

        var foundDisplays: [DisplayInfo] = []

        switch backend {
        case .m1ddc(let path):
            let externalDisplays = discoverM1DDCDisplays(path: path)

            for externalDisplay in externalDisplays {
                guard var reading = queryM1DDCBrightness(
                    displayId: externalDisplay.id,
                    path: path
                ) else {
                    continue
                }

                reading.name = externalDisplay.name

                foundDisplays.append(
                    makeDisplay(id: externalDisplay.id, reading: reading)
                )
            }

        case .ddcctl(let path):
            let discovery = runCommand(path: path, arguments: [])
            guard let ddcDisplayCount = parseExternalDisplayCount(from: discovery.output) else {
                errorMessage = String(localized: "Não foi possível identificar os monitores conectados.")
                return
            }

            let queryableDisplayCount = Swift.min(
                detectedExternalDisplayCount,
                ddcDisplayCount
            )

            if queryableDisplayCount > 0 {
                for displayId in 1...queryableDisplayCount {
                    guard let reading = queryDDCCTLBrightness(displayId: displayId, path: path) else {
                        continue
                    }

                    foundDisplays.append(
                        makeDisplay(id: displayId, reading: reading)
                    )
                }
            }
        }

        displays = foundDisplays

        if foundDisplays.count < detectedExternalDisplayCount {
            let unavailable = detectedExternalDisplayCount - foundDisplays.count
            errorMessage = unavailable == 1
                ? String(localized: "Um monitor foi detectado, mas não respondeu ao DDC/CI.")
                : String(
                    format: String(localized: "%d monitores foram detectados, mas não responderam ao DDC/CI."),
                    unavailable
                )
        }
    }

    func setDisplayBrightness(
        displayId: Int,
        percentage: Double,
        maximumRawBrightness: Int
    ) {
        guard let backend else { return }

        let clampedPercentage = Swift.min(Swift.max(percentage, 0), 100)
        let rawBrightness = Int(
            ((clampedPercentage / 100) * Double(maximumRawBrightness)).rounded()
        )

        let result: CommandResult
        let confirmedReading: BrightnessReading?

        switch backend {
        case .m1ddc(let path):
            result = runCommand(
                path: path,
                arguments: ["display", "\(displayId)", "set", "luminance", "\(rawBrightness)"]
            )
            confirmedReading = result.status == 0
                ? queryM1DDCBrightness(displayId: displayId, path: path)
                : nil

        case .ddcctl(let path):
            result = runCommand(
                path: path,
                arguments: ["-d", "\(displayId)", "-b", "\(rawBrightness)"]
            )
            confirmedReading = result.status == 0
                ? queryDDCCTLBrightness(displayId: displayId, path: path)
                : nil
        }

        guard let confirmedReading else {
            errorMessage = String(localized: "Não foi possível alterar o brilho. Ative o DDC/CI no monitor e confira a conexão.")
            return
        }

        displays.first(where: { $0.id == displayId })?.updateFromReading(
            current: confirmedReading.current,
            maximum: confirmedReading.maximum
        )
        errorMessage = nil
    }

    private func makeDisplay(id: Int, reading: BrightnessReading) -> DisplayInfo {
        DisplayInfo(
            id: id,
            name: reading.name ?? String(
                format: String(localized: "Monitor externo %d"),
                id
            ),
            currentBrightness: reading.current,
            maximumBrightness: reading.maximum
        )
    }

    private func queryM1DDCBrightness(displayId: Int, path: String) -> BrightnessReading? {
        let prefix = ["display", "\(displayId)"]
        let currentResult = runCommand(
            path: path,
            arguments: prefix + ["get", "luminance"]
        )
        let maximumResult = runCommand(
            path: path,
            arguments: prefix + ["max", "luminance"]
        )

        guard currentResult.status == 0,
              maximumResult.status == 0,
              let current = parseStandaloneInteger(from: currentResult.output),
              let maximum = parseStandaloneInteger(from: maximumResult.output),
              maximum > 0,
              current >= 0,
              current <= maximum else {
            return nil
        }

        return BrightnessReading(current: current, maximum: maximum, name: nil)
    }

    private func discoverM1DDCDisplays(path: String) -> [M1DDCDisplay] {
        let result = runCommand(
            path: path,
            arguments: ["display", "list", "detailed"]
        )
        guard result.status == 0 else { return [] }

        var displays: [M1DDCDisplay] = []
        var candidate: M1DDCDisplayCandidate?

        func appendCandidateIfExternal() {
            guard let candidate,
                  candidate.hasExternalLocation || candidate.hasEDID else {
                return
            }

            displays.append(
                M1DDCDisplay(
                    id: candidate.id,
                    name: candidate.name == "(null)" ? nil : candidate.name
                )
            )
        }

        for rawLine in result.output.split(whereSeparator: \Character.isNewline) {
            let line = String(rawLine)

            if let header = firstMatch(
                pattern: #"^\[(\d+)\]\s+(.+?)\s+\("#,
                in: line,
                captureGroups: 2
            ), let id = Int(header[0]) {
                appendCandidateIfExternal()
                candidate = M1DDCDisplayCandidate(
                    id: id,
                    name: header[1].trimmingCharacters(in: .whitespacesAndNewlines)
                )
                continue
            }

            if line.localizedCaseInsensitiveContains("IO Location:")
                && line.localizedCaseInsensitiveContains("dispext") {
                candidate?.hasExternalLocation = true
            }

            if line.localizedCaseInsensitiveContains("EDID UUID:")
                && !line.localizedCaseInsensitiveContains("(null)") {
                candidate?.hasEDID = true
            }
        }

        appendCandidateIfExternal()
        return displays
    }

    private func queryDDCCTLBrightness(displayId: Int, path: String) -> BrightnessReading? {
        let result = runCommand(
            path: path,
            arguments: ["-d", "\(displayId)", "-b", "?"]
        )

        guard result.status == 0,
              let values = firstMatch(
                pattern: #"\bI:\s*VCP control #16 \(0x10\) = current:\s*(\d+),\s*max:\s*(\d+)"#,
                in: result.output,
                captureGroups: 2
              ),
              let current = Int(values[0]),
              let maximum = Int(values[1]),
              maximum > 0,
              current <= maximum else {
            return nil
        }

        let name = firstMatch(
            pattern: #"got edid\.name:\s*([^\r\n]+)"#,
            in: result.output,
            captureGroups: 1
        )?.first?.trimmingCharacters(in: .whitespacesAndNewlines)

        return BrightnessReading(current: current, maximum: maximum, name: name)
    }

    private func locateCommand(possiblePaths: [String]) -> String? {
        // Não busca executáveis no PATH herdado do usuário. Isso evita iniciar
        // um binário homônimo colocado em uma pasta arbitrária.
        return possiblePaths.first(where: fileExistsAndIsExecutable)
    }

    private func fileExistsAndIsExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }

        return FileManager.default.isExecutableFile(atPath: path)
    }

    private func parseExternalDisplayCount(from output: String) -> Int? {
        guard let value = firstMatch(
            pattern: #"found\s+(\d+)\s+external display"#,
            in: output,
            captureGroups: 1
        )?.first else {
            return nil
        }

        return Int(value)
    }

    private func parseStandaloneInteger(from output: String) -> Int? {
        let lines = output.split(whereSeparator: \Character.isNewline)

        for line in lines.reversed() {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Int(value) {
                return number
            }
        }

        return nil
    }

    private func onlineExternalDisplayCount() -> Int? {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success else {
            return nil
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))

        guard CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
            return nil
        }

        return displayIDs
            .prefix(Int(displayCount))
            .filter { CGDisplayIsBuiltin($0) == 0 }
            .count
    }

    private func firstMatch(
        pattern: String,
        in text: String,
        captureGroups: Int
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: text,
                options: [],
                range: NSRange(text.startIndex..., in: text)
              ) else {
            return nil
        }

        var values: [String] = []
        for group in 1...captureGroups {
            guard let range = Range(match.range(at: group), in: text) else {
                return nil
            }
            values.append(String(text[range]))
        }
        return values
    }

    private func runCommand(path: String, arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = commandEnvironment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return CommandResult(status: process.terminationStatus, output: output)
        } catch {
            return CommandResult(status: -1, output: error.localizedDescription)
        }
    }

    private var commandEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.homebrewPath + ":/usr/bin:/bin:/usr/sbin:/sbin"
        return environment
    }
}

private enum BrightnessBackend {
    case m1ddc(String)
    case ddcctl(String)

    var name: String {
        switch self {
        case .m1ddc: return "m1ddc"
        case .ddcctl: return "ddcctl"
        }
    }
}

private struct BrightnessReading {
    let current: Int
    let maximum: Int
    var name: String?
}

private struct M1DDCDisplay {
    let id: Int
    let name: String?
}

private struct M1DDCDisplayCandidate {
    let id: Int
    let name: String
    var hasExternalLocation = false
    var hasEDID = false
}

private struct CommandResult {
    let status: Int32
    let output: String
}
