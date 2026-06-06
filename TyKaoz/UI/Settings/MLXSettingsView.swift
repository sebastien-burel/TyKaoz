import SwiftUI

/// Provider-side settings panel for MLX. Lists curated embedding
/// models, shows installed status + size, and exposes the cache
/// cap slider used by the launch-time LRU pass.
struct MLXSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MLXDownloadCenter.self) private var downloads

    @State private var installed: [MLXModelStore.InstalledModel] = []
    @State private var totalSize: Int64 = 0
    /// Ticks while any download is in flight to force the
    /// `downloadedSizeLabel` to recompute. Without this the
    /// bytes-on-disk counter would only update on the rare events
    /// observed by `downloads.inflight.count` / `removalTick`.
    @State private var diskPollTick: Int = 0

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
        .task(id: downloads.inflight.isEmpty) {
            // 100 ms poll while a download is in flight. The bytes-
            // on-disk counter mostly stays low during the URLSession
            // streaming phase (the daemon cache is outside our
            // sandbox) BUT spikes through several gigabytes during
            // swift-huggingface's `appendFileContents` phase
            // (tmp → `<blob>.incomplete`, 64 KB chunks at SSD
            // speed). At 500 ms we caught one frame of that; at
            // 100 ms we catch enough to feel like real progress.
            while !downloads.inflight.isEmpty {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { break }
                diskPollTick &+= 1
                totalSize = MLXModelStore.shared.totalCacheSize()
            }
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

            if progress != nil {
                // URLSession download temp files live in the
                // nsurlsessiond daemon's cache outside the sandbox,
                // so we can't measure byte-level progress reliably.
                // Show an indeterminate spinner + the actual
                // bytes-on-disk count so the user has something
                // honest to look at.
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Téléchargement en cours…")
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(downloadedSizeLabel(for: model))
                        .font(Brand.Fonts.mono(11))
                        .foregroundStyle(.secondary)
                }
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

    /// "Téléchargé 1,2 Go / 1,6 Go" — honest live counter that
    /// updates as the safetensors gets moved into the HF cache.
    /// Before the final atomic-rename the number stays near 0 (the
    /// bytes are in URLSession's tmp outside the sandbox), then
    /// jumps to ~100 %. Better than a fake percent bar.
    private func downloadedSizeLabel(for model: MLXModelCatalog.Entry) -> String {
        // Reading `diskPollTick` here is what re-subscribes the
        // View to its updates, so the counter refreshes every
        // 500 ms during a download.
        _ = diskPollTick
        let actual = MLXModelStore.shared.sizeOnDisk(modelID: model.id)
        let actualString = ByteCountFormatter.string(fromByteCount: actual, countStyle: .file)
        let expectedString = ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)
        return "\(actualString) / \(expectedString)"
    }
}
