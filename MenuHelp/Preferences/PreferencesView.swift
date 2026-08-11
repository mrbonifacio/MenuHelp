import SwiftUI

struct PreferencesView: View {
    @StateObject private var shortcutService = ShortcutService.shared
    @StateObject private var clipboardService = ClipboardService.shared
    @State private var isClearHistoryConfirmationPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                preferenceHeader(
                    icon: "keyboard",
                    title: "Atalhos",
                    subtitle: "Acesse recursos do MenuHelp em qualquer aplicativo."
                )

                VStack(spacing: 0) {
                    Toggle(
                        "Ativar todos os atalhos",
                        isOn: Binding(
                            get: { shortcutService.areAllShortcutsEnabled },
                            set: { shortcutService.setAllShortcutsEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .padding(14)

                    Divider().padding(.leading, 14)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Histórico do Clipboard")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Abra, navegue com ↑/↓ e confirme com Enter")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        ShortcutKeyCaps()

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { shortcutService.isClipboardHistoryShortcutEnabled },
                                set: { shortcutService.setClipboardHistoryShortcutEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!shortcutService.areAllShortcutsEnabled)
                    }
                    .padding(14)
                    .opacity(shortcutService.areAllShortcutsEnabled ? 1 : 0.55)
                }
                .background(Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let registrationError = shortcutService.registrationError {
                    Label(registrationError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                preferenceHeader(
                    icon: "clipboard",
                    title: "Histórico do Clipboard",
                    subtitle: "Controle o armazenamento local de textos e imagens."
                )

                VStack(spacing: 0) {
                    Toggle(
                        "Registrar novos itens",
                        isOn: Binding(
                            get: { clipboardService.isEnabled },
                            set: { clipboardService.setEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .padding(14)

                    Divider().padding(.leading, 14)

                    settingPickerRow(title: "Máximo de itens") {
                        Picker(
                            "Máximo de itens",
                            selection: Binding(
                                get: { clipboardService.maxItemCount },
                                set: { clipboardService.setMaxItemCount($0) }
                            )
                        ) {
                            ForEach(ClipboardService.itemCountOptions, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }

                    Divider().padding(.leading, 14)

                    settingPickerRow(title: "Excluir automaticamente") {
                        Picker(
                            "Excluir automaticamente",
                            selection: Binding(
                                get: { clipboardService.retentionDays },
                                set: { clipboardService.setRetentionDays($0) }
                            )
                        ) {
                            ForEach(ClipboardService.retentionDayOptions, id: \.self) { days in
                                Text(retentionLabel(for: days)).tag(days)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }

                    Divider().padding(.leading, 14)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apagar histórico")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Remove imediatamente todos os textos e imagens salvos.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Apagar…", role: .destructive) {
                            isClearHistoryConfirmationPresented = true
                        }
                        .disabled(clipboardService.items.isEmpty)
                    }
                    .padding(14)
                }
                .background(Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Label(
                    "O histórico fica somente neste Mac. Itens confidenciais ou transitórios são ignorados, imagens usam no máximo 200 MB e nenhum conteúdo é enviado pela internet.",
                    systemImage: "lock.shield"
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(width: 520, height: 590)
        .confirmationDialog(
            "Apagar todo o histórico?",
            isPresented: $isClearHistoryConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Apagar todo o histórico", role: .destructive) {
                clipboardService.clearHistory()
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Essa ação remove os textos e as imagens armazenados pelo MenuHelp e não pode ser desfeita.")
        }
    }

    private func preferenceHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func settingPickerRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            content()
        }
        .padding(14)
    }

    private func retentionLabel(for days: Int) -> String {
        days == 0 ? "Nunca" : "\(days) dias"
    }
}

private struct ShortcutKeyCaps: View {
    var body: some View {
        HStack(spacing: 4) {
            keyCap("⇧")
            keyCap("⌘")
            keyCap("V")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shift Command V")
    }

    private func keyCap(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 23, minHeight: 22)
            .background(Color.primary.opacity(0.09))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
