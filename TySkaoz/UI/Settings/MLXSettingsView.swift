import SwiftUI

/// Provider-side settings panel for MLX. Lists curated embedding
/// models, shows installed status + size, and exposes the cache
/// cap slider used by the launch-time LRU pass.
struct MLXSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MLXDownloadCenter.self) private var downloads

    @State private var installed: [MLXModelStore.InstalledModel] = []
    @State private var totalSize: Int64 = 0

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Cache") {
                cacheUsageRow

                Stepper(
                    value: $settings.mlxCacheCapGB,
                    in: 1...100,
                    step: 1
                ) {
                    Text("Plafond du cache : \(Int(settings.mlxCacheCapGB)) Go")
                }
                Text("""
                Une fois ce plafond dépassé, le modèle le moins \
                récemment utilisé est supprimé au prochain lancement.
                """)
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)

                if let root = MLXModelStore.shared.hubCacheRoot() {
                    Text("Emplacement : \(root.path)")
                        .font(Brand.Fonts.mono(11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Modèles d'embedding") {
                ForEach(MLXModelCatalog.embeddings) { model in
                    modelRow(model)
                }
            }

            Section("Modèles de chat") {
                ForEach(MLXModelCatalog.chats) { model in
                    modelRow(model)
                }
            }

            if !customInstalledModels.isEmpty {
                Section("Modèles personnalisés") {
                    ForEach(customInstalledModels, id: \.modelID) { model in
                        customRow(model)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task(id: downloads.removalTick) {
            refresh()
        }
        .task(id: downloads.inflight.count) {
            refresh()
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var cacheUsageRow: some View {
        let capBytes = Int64(settings.mlxCacheCapGB * 1024 * 1024 * 1024)
        let used = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        let cap  = ByteCountFormatter.string(fromByteCount: capBytes, countStyle: .file)
        let pct  = capBytes > 0 ? Double(totalSize) / Double(capBytes) : 0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Utilisé", systemImage: "internaldrive")
                Spacer()
                Text("\(used) / \(cap)")
                    .font(Brand.Fonts.mono(12))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(pct, 1))
                .progressViewStyle(.linear)
                .tint(pct > 0.9 ? .orange : .accentColor)
        }
    }

    @ViewBuilder
    private func modelRow(_ model: MLXModelCatalog.Entry) -> some View {
        let isInstalled = MLXModelStore.shared.isInstalled(modelID: model.id)
        let progress = downloads.inflight[model.id]
        let error = downloads.lastError[model.id]

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(Brand.Fonts.body(13).weight(.medium))
                        if model.isVision {
                            Text("VLM")
                                .font(Brand.Fonts.mono(10).weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(model.summary)
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(model.id)
                            .font(Brand.Fonts.mono(11))
                            .foregroundStyle(.secondary)
                        if let dim = model.dimension {
                            Text("· dim \(dim)")
                                .font(Brand.Fonts.body(11))
                                .foregroundStyle(.secondary)
                        }
                        Text("· ≈\(ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file))")
                            .font(Brand.Fonts.body(11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                actions(for: model, isInstalled: isInstalled, progress: progress)
            }

            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("Téléchargement… \(Int(progress * 100)) %")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.orange)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actions(
        for model: MLXModelCatalog.Entry,
        isInstalled: Bool,
        progress: Double?
    ) -> some View {
        if progress != nil {
            Button("Annuler") {
                downloads.cancel(model.id)
            }
        } else if isInstalled {
            Menu {
                Button("Re-télécharger") {
                    downloads.remove(model.id)
                    Task { _ = try? await downloads.download(model.id) }
                }
                Button("Supprimer", role: .destructive) {
                    downloads.remove(model.id)
                }
            } label: {
                Label("Installé", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            Button {
                Task { _ = try? await downloads.download(model.id) }
            } label: {
                Label("Télécharger", systemImage: "arrow.down.circle")
            }
        }
    }

    @ViewBuilder
    private func customRow(_ model: MLXModelStore.InstalledModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.modelID)
                    .font(Brand.Fonts.mono(12))
                Text(ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file))
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                downloads.remove(model.modelID)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Data

    /// Models installed on disk that aren't in the curated list —
    /// users who typed a custom HF slug in the wiki settings end up
    /// here. Letting them clean up via this panel keeps the cache
    /// honest.
    private var customInstalledModels: [MLXModelStore.InstalledModel] {
        let curated = Set(
            (MLXModelCatalog.embeddings + MLXModelCatalog.chats).map(\.id)
        )
        return installed.filter { !curated.contains($0.modelID) }
    }

    private func refresh() {
        installed = MLXModelStore.shared.installedModels()
        totalSize = MLXModelStore.shared.totalCacheSize()
    }
}
