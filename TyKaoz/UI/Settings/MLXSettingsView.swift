import SwiftUI
import MLX

/// Provider-side settings panel for MLX. Lists curated embedding
/// models, shows installed status + size, and exposes the cache
/// cap slider used by the launch-time LRU pass.
struct MLXSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MLXDownloadCenter.self) private var downloads
    @Environment(ModelCatalogService.self) private var catalog

    @State private var installed: [MLXModelStore.InstalledModel] = []
    @State private var totalSize: Int64 = 0
    /// Real-conditions RAM probes keyed by model ID, plus in-flight /
    /// error state, driven by the per-model "Mesurer la RAM" action.
    @State private var measurements: [String: MLXChatActor.MemoryReport] = [:]
    @State private var measuring: Set<String> = []
    @State private var measureError: [String: String] = [:]
    /// Draft slug in the "add a custom model" field.
    @State private var customID: String = ""

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

                Button {
                    Task {
                        await MLXChatActor.unloadAll()
                        await MLXEmbeddingActor.unloadAll()
                        MLX.GPU.clearCache()
                    }
                } label: {
                    Label("Décharger les modèles en mémoire", systemImage: "eject")
                }
                Text("""
                Libère immédiatement la RAM GPU occupée par les modèles \
                chargés. Sinon, un modèle inactif se décharge tout seul \
                après 5 min.
                """)
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
            }

            Section("Modèles d'embedding") {
                ForEach(catalog.embeddings) { model in
                    modelRow(model)
                }
            }

            Section("Modèles de chat") {
                ForEach(catalog.chats) { model in
                    modelRow(model)
                }
            }

            Section("Modèles personnalisés") {
                addCustomRow
                ForEach(customModelIDs, id: \.self) { id in
                    customModelRow(id)
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
            // Keep the cache "Utilisé" gauge moving while a download is
            // in flight (per-model progress now comes from the live
            // fraction in `downloads.inflight`).
            while !downloads.inflight.isEmpty {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { break }
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
    private func modelRow(_ model: CatalogModel) -> some View {
        let isInstalled = MLXModelStore.shared.isInstalled(modelID: model.id)
        let progress = downloads.inflight[model.id]
        let error = downloads.lastError[model.id]

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
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
                    Text(model.description)
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
                    ramWarning(for: model)
                    memoryReadout(for: model)
                }
                Spacer()
                actions(for: model, isInstalled: isInstalled, progress: progress)
            }

            if let progress {
                // Real byte-weighted progress forwarded from
                // swift-huggingface (sampled ~10×/s during transfer).
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: min(max(progress, 0), 1))
                        .progressViewStyle(.linear)
                    HStack {
                        Text("Téléchargement en cours…")
                            .font(Brand.Fonts.body(11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(downloadProgressLabel(progress, of: model.sizeBytes))
                            .font(Brand.Fonts.mono(11))
                            .foregroundStyle(.secondary)
                    }
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

    /// Result of the real-conditions RAM probe: a spinner while it
    /// runs, then measured resident/peak footprint plus a suggested
    /// `min/recommended_ram_gb` (peak + OS headroom) to drop into the
    /// manifest. Only chat models are probed (they load via
    /// `MLXChatActor`); embedders are sized differently.
    @ViewBuilder
    private func memoryReadout(for model: CatalogModel) -> some View {
        if measuring.contains(model.id) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Mesure de la mémoire…")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }
        } else if let report = measurements[model.id] {
            let resident = ByteCountFormatter.string(fromByteCount: Int64(report.residentBytes), countStyle: .memory)
            let peak = ByteCountFormatter.string(fromByteCount: Int64(report.peakBytes), countStyle: .memory)
            let peakGB = Double(report.peakBytes) / 1_073_741_824
            let minSug = Int(peakGB.rounded(.up)) + 4
            let recSug = Int(peakGB.rounded(.up)) + 8
            VStack(alignment: .leading, spacing: 1) {
                Text("Mémoire mesurée — résident \(resident) · pic \(peak)")
                    .font(Brand.Fonts.mono(11))
                    .foregroundStyle(.secondary)
                Text("Suggéré — min ~\(minSug) Go · conseillé ~\(recSug) Go")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
        }
        if let err = measureError[model.id] {
            Label(err, systemImage: "exclamationmark.triangle")
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.orange)
                .lineLimit(3)
        }
    }

    /// Loads the model and measures its real memory footprint. No-op if
    /// a probe is already running for this model.
    private func measure(_ model: CatalogModel) {
        guard !measuring.contains(model.id) else { return }
        measuring.insert(model.id)
        measureError[model.id] = nil
        Task {
            do {
                measurements[model.id] = try await MLXChatActor.shared(for: model.id).measureMemory()
            } catch {
                measureError[model.id] = error.localizedDescription
            }
            measuring.remove(model.id)
        }
    }

    /// Orange notice when the model's declared minimum RAM exceeds this
    /// machine's physical memory — it likely won't run. We warn rather
    /// than hide: the floor is approximate and the user may know better.
    @ViewBuilder
    private func ramWarning(for model: CatalogModel) -> some View {
        if let need = model.minRamGB, need > Self.machineRAMGB {
            Label(
                "Nécessite ~\(need) Go de RAM (cette machine : \(Self.machineRAMGB) Go).",
                systemImage: "exclamationmark.triangle"
            )
            .font(Brand.Fonts.body(11))
            .foregroundStyle(.orange)
        }
    }

    /// Physical memory in whole gigabytes (1 Go = 1024³).
    private static let machineRAMGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))

    @ViewBuilder
    private func actions(
        for model: CatalogModel,
        isInstalled: Bool,
        progress: Double?
    ) -> some View {
        if progress != nil {
            Button("Annuler") {
                downloads.cancel(model.id)
            }
        } else if isInstalled {
            Menu {
                if model.category == .chat {
                    Button("Mesurer la RAM") { measure(model) }
                }
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

    /// Text field + button to register a HuggingFace MLX chat model
    /// by exact slug, then immediately start downloading it.
    @ViewBuilder
    private var addCustomRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                TextField("Ajouter un modèle HuggingFace (ex : mlx-community/gpt-oss-20b-MXFP4-Q4)", text: $customID)
                    .textFieldStyle(.plain)
                    .font(Brand.Fonts.mono(12))
                    .onSubmit(addCustomModel)
                Button("Ajouter", action: addCustomModel)
                    .disabled(customID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("""
            Le slug doit être un dépôt MLX (poids quantifiés MLX). Le \
            modèle est traité comme un modèle de chat et téléchargé \
            immédiatement.
            """)
            .font(Brand.Fonts.body(11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func customModelRow(_ id: String) -> some View {
        let isInstalled = MLXModelStore.shared.isInstalled(modelID: id)
        let progress = downloads.inflight[id]
        let error = downloads.lastError[id]
        let size = installed.first { $0.modelID == id }?.sizeBytes

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(id)
                        .font(Brand.Fonts.mono(12))
                        .textSelection(.enabled)
                    if let size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(Brand.Fonts.body(11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                customActions(id: id, isInstalled: isInstalled, progress: progress)
            }

            if let progress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: min(max(progress, 0), 1))
                        .progressViewStyle(.linear)
                    HStack {
                        Text("Téléchargement en cours…")
                            .font(Brand.Fonts.body(11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((progress * 100).rounded())) %")
                            .font(Brand.Fonts.mono(11))
                            .foregroundStyle(.secondary)
                    }
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
    private func customActions(id: String, isInstalled: Bool, progress: Double?) -> some View {
        if progress != nil {
            Button("Annuler") { downloads.cancel(id) }
        } else if isInstalled {
            Menu {
                Button("Re-télécharger") {
                    downloads.remove(id)
                    Task { _ = try? await downloads.download(id) }
                }
                Button("Supprimer", role: .destructive) {
                    downloads.remove(id)
                    settings.removeCustomMLXChatModel(id)
                }
            } label: {
                Label("Installé", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            HStack(spacing: 8) {
                Button {
                    Task { _ = try? await downloads.download(id) }
                } label: {
                    Label("Télécharger", systemImage: "arrow.down.circle")
                }
                Button(role: .destructive) {
                    settings.removeCustomMLXChatModel(id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func addCustomModel() {
        guard let id = settings.addCustomMLXChatModel(customID) else { return }
        customID = ""
        Task { _ = try? await downloads.download(id) }
    }

    // MARK: - Data

    /// Custom chat slugs to list: the ones the user registered, plus
    /// any off-catalog model already on disk (e.g. typed in the wiki
    /// settings before this panel existed), so the cache stays honest.
    private var customModelIDs: [String] {
        let curated = Set(catalog.models.map(\.id))
        let orphans = installed.map(\.modelID).filter { !curated.contains($0) }
        var seen = Set<String>()
        return (settings.mlxCustomChatModelIDs + orphans).filter {
            !curated.contains($0) && seen.insert($0).inserted
        }
    }

    private func refresh() {
        installed = MLXModelStore.shared.installedModels()
        totalSize = MLXModelStore.shared.totalCacheSize()
    }

    /// "1,2 Go / 1,6 Go · 75 %" derived from the live download fraction
    /// and the catalog's expected size.
    private func downloadProgressLabel(_ fraction: Double, of expectedBytes: Int64) -> String {
        let done = Int64(Double(expectedBytes) * min(max(fraction, 0), 1))
        let doneString = ByteCountFormatter.string(fromByteCount: done, countStyle: .file)
        let expectedString = ByteCountFormatter.string(fromByteCount: expectedBytes, countStyle: .file)
        return "\(doneString) / \(expectedString) · \(Int((fraction * 100).rounded())) %"
    }
}
