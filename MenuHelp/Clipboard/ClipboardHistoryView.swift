//
//  ClipboardHistoryView.swift
//  MenuHelp
//
//  Created on 28/01/2026.
//

import SwiftUI

struct ClipboardHistoryView: View {
    @StateObject private var clipboardService = ClipboardService.shared
    @State private var selectedItemID: UUID?
    @State private var isClearHistoryConfirmationPresented = false
    @FocusState private var keyboardNavigationFocused: Bool

    let selectionRequestID: UUID?
    let onConfirm: (ClipboardItem) -> Void

    init(
        selectionRequestID: UUID? = nil,
        onConfirm: @escaping (ClipboardItem) -> Void = {
            ClipboardService.shared.copyToClipboard($0)
        }
    ) {
        self.selectionRequestID = selectionRequestID
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(spacing: 0) {
            // Cabeçalho com busca
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Buscar no histórico...", text: $clipboardService.searchText)
                    .textFieldStyle(.plain)

                if !clipboardService.items.isEmpty {
                    Button {
                        isClearHistoryConfirmationPresented = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Apagar todo o histórico")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))

            Divider()

            if !clipboardService.isEnabled {
                VStack(spacing: 14) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)

                    Text("Histórico desativado")
                        .font(.headline)

                    Text("Ative o histórico para registrar textos e imagens copiados.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Ativar histórico") {
                        clipboardService.setEnabled(true)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if clipboardService.filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Nenhum item no histórico")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(clipboardService.filteredItems) { item in
                                ClipboardItemRow(
                                    item: item,
                                    image: clipboardService.image(for: item)
                                ) {
                                    selectedItemID = item.id
                                    confirm(item)
                                }
                                .background(
                                    selectedItemID == item.id
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.clear
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedItemID = item.id
                                    confirm(item)
                                }
                                .id(item.id)

                                Divider()
                            }
                        }
                    }
                    .onChange(of: selectedItemID) { _, newSelection in
                        guard let newSelection else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newSelection, anchor: .center)
                        }
                    }
                }

                if selectionRequestID != nil {
                    HStack(spacing: 12) {
                        Label("Navegar", systemImage: "arrow.up.arrow.down")
                        Label("Colar", systemImage: "return")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.045))
                    .overlay(alignment: .top) {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($keyboardNavigationFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            confirmSelectedItem()
            return .handled
        }
        .onChange(of: selectionRequestID) { _, newRequest in
            guard newRequest != nil else { return }
            prepareKeyboardSelection()
        }
        .onChange(of: clipboardService.filteredItems.map(\.id)) { _, itemIDs in
            guard !itemIDs.isEmpty else {
                selectedItemID = nil
                return
            }

            if let selectedItemID, itemIDs.contains(selectedItemID) {
                return
            }

            selectedItemID = itemIDs.first
        }
        .onAppear {
            if selectionRequestID != nil {
                prepareKeyboardSelection()
            }
        }
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
            Text("Os textos e as imagens salvos serão removidos permanentemente.")
        }
    }

    private func prepareKeyboardSelection() {
        selectedItemID = clipboardService.filteredItems.first?.id
        DispatchQueue.main.async {
            keyboardNavigationFocused = true
        }
    }

    private func moveSelection(by offset: Int) {
        let items = clipboardService.filteredItems
        guard !items.isEmpty else { return }

        guard let selectedItemID,
              let currentIndex = items.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = items.first?.id
            return
        }

        let newIndex = Swift.min(
            Swift.max(currentIndex + offset, items.startIndex),
            items.index(before: items.endIndex)
        )
        self.selectedItemID = items[newIndex].id
    }

    private func confirmSelectedItem() {
        guard let selectedItemID,
              let item = clipboardService.filteredItems.first(where: {
                $0.id == selectedItemID
              }) else {
            return
        }

        confirm(item)
    }

    private func confirm(_ item: ClipboardItem) {
        onConfirm(item)
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let image: NSImage?
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if item.kind == .image {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 160, alignment: .leading)
                            .cornerRadius(6)
                            .accessibilityLabel("Imagem copiada")
                    } else {
                        Label("Imagem indisponível", systemImage: "photo.badge.exclamationmark")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(item.preview)
                        .font(.system(size: 13))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Text(item.timestampString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Copiar novamente")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
