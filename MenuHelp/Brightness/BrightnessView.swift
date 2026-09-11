//
//  BrightnessView.swift
//  MenuHelp
//

import SwiftUI

struct BrightnessSection: View {
    @StateObject private var brightnessService = BrightnessService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Brilho dos monitores externos", systemImage: "display.2")
                    .font(.headline)

                Spacer()

                Button {
                    brightnessService.checkBackendAvailability()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Verificar monitores novamente")
            }

            if !brightnessService.backendAvailable {
                compactMessage(
                    icon: "exclamationmark.triangle",
                    title: requiredBackendTitle,
                    detail: requiredBackendDescription
                )
            } else if brightnessService.displays.isEmpty {
                compactMessage(
                    icon: brightnessService.detectedExternalDisplayCount > 0
                        ? "display.trianglebadge.exclamationmark"
                        : "display",
                    title: emptyStateTitle,
                    detail: emptyStateDescription
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(brightnessService.displays) { display in
                        DisplayBrightnessControl(display: display)
                    }
                }

                if let errorMessage = brightnessService.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(14)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .onAppear {
            // Evita alterar o conteúdo do popover durante o primeiro passe de layout.
            DispatchQueue.main.async {
                brightnessService.checkBackendAvailability()
            }
        }
    }

    private func compactMessage(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyStateTitle: String {
        if brightnessService.detectedExternalDisplayCount == 0 {
            return String(localized: "Nenhum monitor externo detectado")
        }

        return brightnessService.detectedExternalDisplayCount == 1
            ? String(localized: "Monitor sem controle DDC/CI")
            : String(localized: "Monitores sem controle DDC/CI")
    }

    private var emptyStateDescription: String {
        if brightnessService.detectedExternalDisplayCount == 0 {
            return String(localized: "Conecte um monitor externo compatível com DDC/CI.")
        }

        return brightnessService.errorMessage
            ?? String(localized: "Ative o DDC/CI no monitor e confira o cabo ou adaptador.")
    }

    private var requiredBackendTitle: String {
        String(localized: "Controle de brilho indisponível")
    }

    private var requiredBackendDescription: String {
        String(localized: "Reinstale o MenuHelp para restaurar o componente de brilho incluído no app.")
    }
}

struct DisplayBrightnessControl: View {
    @ObservedObject var display: DisplayInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(display.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(display.brightness))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 9) {
                Image(systemName: "moon")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Slider(
                    value: Binding(
                        get: { display.brightness },
                        set: { display.updatePreview($0) }
                    ),
                    in: 0...100,
                    step: 1,
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            display.commitBrightness()
                        }
                    }
                )

                Image(systemName: "sun.max.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
