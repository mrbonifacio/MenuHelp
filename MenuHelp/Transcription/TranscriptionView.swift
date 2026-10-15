import SwiftUI

struct TranscriptionView: View {
    @ObservedObject private var service = TranscriptionService.shared
    @State private var isHelpExpanded = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    controls
                    recordingStatus
                    transcript
                        .frame(height: max(160, geometry.size.height - 360))

                    if let errorMessage = service.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    outputFile
                    permissionHelp
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Transcrever áudio do computador")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Transcreva o som de aplicativos, navegadores e reuniões com tempos e histórico completo em TXT. O microfone não é capturado.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Idioma do áudio")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Idioma do áudio", selection: $service.selectedLocaleIdentifier) {
                    ForEach(service.availableLocales, id: \.identifier) { locale in
                        Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(service.isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if service.state == .preparing {
                Button("Cancelar") {
                    service.stop()
                }
                .buttonStyle(.bordered)
            } else if service.isRecording {
                Button {
                    service.stop()
                } label: {
                    Label("Parar e salvar", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button {
                    service.start()
                } label: {
                    Label(startButtonTitle, systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(service.isBusy || service.availableLocales.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var recordingStatus: some View {
        HStack(spacing: 8) {
            if service.state == .preparing || service.state == .stopping {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(service.isRecording ? Color.red : Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }

            Text(statusTitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if service.isRecording {
                ProgressView(value: service.audioLevel, total: 1)
                    .progressViewStyle(.linear)
                    .tint(.green)
                    .frame(width: 65)
                    .accessibilityLabel("Nível do áudio do computador")
                    .accessibilityValue(String(format: String(localized: "%d por cento"), Int(service.audioLevel * 100)))
            }

            if service.isBusy || service.elapsedSeconds > 0 {
                Text(elapsedTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel(
                        String(format: String(localized: "Duração: %d segundos"), service.elapsedSeconds)
                    )
            }
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Histórico da transcrição")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                if service.isRecording {
                    Text("Ao vivo")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.025))

            Divider()

            if service.transcript.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 25))
                        .accessibilityHidden(true)
                    Text(emptyTranscriptTitle)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.secondary)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(service.transcript)
                                .font(.system(size: 14))
                                .lineSpacing(5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                            Color.clear.frame(height: 1).id("transcription-bottom")
                        }
                    }
                    .onChange(of: service.recognizedSegmentCount) { _, _ in
                        if service.isRecording {
                            proxy.scrollTo("transcription-bottom", anchor: .bottom)
                        }
                    }
                }
                .accessibilityLabel("Histórico da transcrição")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var outputFile: some View {
        if let fileURL = service.fileURL {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    service.hasUnsavedChanges && !service.isBusy
                        ? String(localized: "Texto pendente de salvamento")
                        : service.isBusy ? String(localized: "Salvando automaticamente em TXT") : String(localized: "Histórico completo salvo em TXT"),
                    systemImage: "doc.text"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Text(fileURL.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(fileURL.path)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Mostrar no Finder") {
                        service.revealFile()
                    }
                    .controlSize(.small)

                    Button("Salvar cópia…") {
                        service.saveCopy()
                    }
                    .controlSize(.small)
                    .disabled(service.isBusy || service.transcript.isEmpty)
                }
            }
        } else {
            Label("O TXT registra o início, os trechos com tempo e o encerramento da sessão.", systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionHelp: some View {
        DisclosureGroup("Permissões e ajuda", isExpanded: $isHelpExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ao iniciar, autorize a gravação de áudio do sistema e o reconhecimento de fala. Escolha o idioma falado e reproduza o áudio que deseja transcrever.")
                Text("Se uma permissão foi negada, habilite o MenuHelp nos Ajustes do Sistema. Pode ser necessário reabrir o aplicativo.")
                HStack(spacing: 12) {
                    Button("Permissão de captura") {
                        service.openCaptureSettings()
                    }
                    Button("Reconhecimento de fala") {
                        service.openSpeechSettings()
                    }
                }
                .controlSize(.small)

                Text("Áudio protegido ou bloqueado pela plataforma pode não estar disponível. A captura inclui os outros sons do computador; fechar esta janela mantém a transcrição ativa.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        }
        .font(.caption)
    }

    private var startButtonTitle: String {
        service.fileURL == nil
            ? String(localized: "Iniciar transcrição")
            : String(localized: "Nova transcrição")
    }

    private var statusTitle: String {
        switch service.state {
        case .idle:
            return service.fileURL == nil
                ? String(localized: "Pronto para transcrever")
                : String(localized: "Transcrição encerrada")
        case .preparing:
            return service.preparationMessage
        case .recording:
            return service.hasReceivedAudio
                ? String(localized: "Capturando áudio do computador")
                : String(localized: "Aguardando som do computador…")
        case .stopping:
            return String(localized: "Finalizando e salvando…")
        }
    }

    private var emptyTranscriptTitle: String {
        service.isBusy
            ? String(localized: "As palavras aparecerão aqui conforme o áudio for reconhecido.")
            : String(localized: "Inicie a transcrição e reproduza um áudio no computador.")
    }

    private var elapsedTime: String {
        let seconds = max(0, service.elapsedSeconds)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds % 60)
        }
        return String(format: "%02d:%02d", minutes, seconds % 60)
    }
}
