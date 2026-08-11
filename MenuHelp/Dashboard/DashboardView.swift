import SwiftUI

struct DashboardView: View {
    @StateObject private var systemMonitor = SystemMonitorService.shared
    @StateObject private var clipboardService = ClipboardService.shared
    @StateObject private var keyboardCleaning = KeyboardCleaningService.shared
    @StateObject private var preventSleep = PreventSleepService.shared

    let openClipboardHistory: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if systemMonitor.isEnabled {
                    SystemMetricsView(service: systemMonitor)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack(spacing: 0) {
                    FeatureToggleRow(
                        title: "Monitoramento do sistema",
                        subtitle: "CPU, memória e disco",
                        isOn: Binding(
                            get: { systemMonitor.isEnabled },
                            set: { systemMonitor.setEnabled($0) }
                        )
                    )

                    Divider().padding(.leading, 14)

                    FeatureToggleRow(
                        title: "Histórico do Clipboard",
                        subtitle: clipboardService.isEnabled
                            ? "\(clipboardService.items.count) itens salvos"
                            : "Textos e imagens não serão registrados",
                        isOn: Binding(
                            get: { clipboardService.isEnabled },
                            set: { clipboardService.setEnabled($0) }
                        )
                    )

                    if clipboardService.isEnabled {
                        Button(action: openClipboardHistory) {
                            HStack {
                                Label("Abrir histórico", systemImage: "clock.arrow.circlepath")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().padding(.leading, 14)

                    FeatureToggleRow(
                        title: "Limpeza do teclado",
                        subtitle: keyboardSubtitle,
                        isOn: Binding(
                            get: { keyboardCleaning.isEnabled },
                            set: { keyboardCleaning.setEnabled($0) }
                        )
                    )

                    if let errorMessage = keyboardCleaning.errorMessage {
                        InlineWarning(text: errorMessage)
                    }

                    Divider().padding(.leading, 14)

                    FeatureToggleRow(
                        title: "Prevent Sleep",
                        subtitle: "Impede o repouso automático do Mac",
                        isOn: Binding(
                            get: { preventSleep.isEnabled },
                            set: { preventSleep.setEnabled($0) }
                        )
                    )

                    if let errorMessage = preventSleep.errorMessage {
                        InlineWarning(text: errorMessage)
                    }
                }
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

                BrightnessSection()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .animation(.easeInOut(duration: 0.2), value: systemMonitor.isEnabled)
    }

    private var keyboardSubtitle: String {
        if keyboardCleaning.isEnabled {
            return "Teclado bloqueado por mais \(keyboardCleaning.secondsRemaining)s"
        }
        return "Bloqueia as teclas por 30 segundos"
    }
}

private struct SystemMetricsView: View {
    @ObservedObject var service: SystemMonitorService

    var body: some View {
        HStack(spacing: 18) {
            MetricRing(title: "CPU", icon: "cpu", value: service.cpuUsage)
            MetricRing(title: "RAM", icon: "memorychip", value: service.memoryUsage)
            MetricRing(title: "DISCO", icon: "internaldrive", value: service.diskUsage)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

private struct MetricRing: View {
    let title: String
    let icon: String
    let value: Double

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: value)
                    .stroke(
                        Color.green,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                    Text("\(Int(value * 100))%")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(width: 58, height: 58)

            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(Int(value * 100)) por cento")
    }
}

private struct FeatureToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct InlineWarning: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
    }
}
