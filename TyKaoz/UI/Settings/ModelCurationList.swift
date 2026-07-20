import SwiftUI

/// Compact "Modèles" section shown in every per-provider panel: the active
/// model picker (limited to enabled models) + a small summary line + a
/// "Gérer les modèles…" button that opens a sheet for curation.
struct ModelCurationSummary: View {
    @Environment(AppSettings.self) private var settings

    let provider: ProviderID
    let allModelIDs: [String]
    @Binding var activeModel: String?

    @State private var showSheet = false

    var body: some View {
        let enabled = settings.enabledModels(for: provider).sorted()

        Section("Modèles") {
            if enabled.isEmpty {
                Text("Aucun modèle activé. Ouvre « Gérer les modèles… » pour en choisir.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            } else {
                Picker("Modèle actif", selection: $activeModel) {
                    Text("Aucun").tag(String?.none)
                    ForEach(enabled, id: \.self) { id in
                        Text(id).tag(String?.some(id))
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text(summary(enabled: enabled.count, total: allModelIDs.count))
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Gérer les modèles…") { showSheet = true }
                    .disabled(allModelIDs.isEmpty)
            }
        }
        .sheet(isPresented: $showSheet) {
            ModelCurationSheet(provider: provider, allModelIDs: allModelIDs)
        }
    }

    private func summary(enabled: Int, total: Int) -> String {
        if total == 0 {
            return "Teste la connexion pour récupérer la liste."
        }
        return "\(enabled) activé(s) sur \(total) disponible(s)."
    }
}

/// Full-screen modal sheet to curate which models from a provider's catalog
/// are enabled for use in TyKaoz. Includes a search field and a heuristic
/// filter toggle.
struct ModelCurationSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let provider: ProviderID
    let allModelIDs: [String]

    @State private var search: String = ""
    @State private var showAll: Bool = false
    @State private var customID: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Brand.Colors.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Modèles \(provider.displayName)")
                    .font(Brand.Fonts.title(18).italic())
                    .foregroundStyle(Brand.Colors.ink)
                Spacer()
                Toggle("Tout afficher", isOn: $showAll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(Brand.Fonts.body(12))
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filtrer", text: $search)
                    .textFieldStyle(.plain)
                    .font(Brand.Fonts.body(13))
            }
            .padding(8)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Brand.Colors.slate.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Add a model the provider's /models endpoint doesn't list
            // (e.g. image models like cogview-*, qwen-image-*). The id is
            // enabled directly and shows in the list below.
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                TextField("Ajouter un modèle par id exact…", text: $customID)
                    .textFieldStyle(.plain)
                    .font(Brand.Fonts.body(13))
                    .onSubmit(addCustomModel)
                Button("Ajouter", action: addCustomModel)
                    .disabled(customID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Brand.Colors.slate.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
    }

    private func addCustomModel() {
        let id = customID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        settings.setEnabled(true, modelID: id, for: provider)
        customID = ""
        search = ""
    }

    private var filteredIDs: [String] {
        // Include enabled ids the catalog doesn't list (manually added),
        // so they appear and stay toggleable.
        let enabled = settings.enabledModels(for: provider)
        let extras = enabled.filter { !allModelIDs.contains($0) }
        let matches = (allModelIDs + extras).filter { id in
            !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (showAll || ModelHeuristic.isLikelyChatModel(id: id, provider: provider) || enabled.contains(id))
                && (search.isEmpty || id.localizedCaseInsensitiveContains(search))
        }
        // The catalog can hold duplicates (e.g. the Mistral /models endpoint
        // lists some ids twice); collapse them so each model shows once and
        // the List's `id: \.self` identity stays unique.
        var seen = Set<String>()
        return matches.filter { seen.insert($0).inserted }
    }

    private var list: some View {
        let enabled = settings.enabledModels(for: provider)
        let ids = filteredIDs

        return Group {
            if ids.isEmpty {
                Text(allModelIDs.isEmpty
                     ? "Catalogue vide — testez la connexion d'abord."
                     : "Aucun modèle ne correspond à ce filtre.")
                    .font(Brand.Fonts.body(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
            } else {
                List(ids, id: \.self) { id in
                    row(for: id, isEnabled: enabled.contains(id))
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Brand.Colors.paper)
    }

    private func row(for id: String, isEnabled: Bool) -> some View {
        let isChat = ModelHeuristic.isLikelyChatModel(id: id, provider: provider)
        return Toggle(isOn: Binding(
            get: { isEnabled },
            set: { settings.setEnabled($0, modelID: id, for: provider) }
        )) {
            HStack(spacing: 8) {
                Text(id)
                    .font(Brand.Fonts.body(13))
                    .foregroundStyle(Brand.Colors.ink)
                if !isChat {
                    Text("(non-chat)")
                        .font(Brand.Fonts.body(10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .toggleStyle(.checkbox)
    }

    private var footer: some View {
        HStack {
            let total = allModelIDs.count
            let enabled = settings.enabledModels(for: provider).count
            let hidden = showAll ? 0 : (total - filteredIDsCount(applyingSearch: false))

            Text("\(enabled) activé(s) sur \(total)" + (hidden > 0 ? " · \(hidden) masqué(s) par le filtre" : ""))
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)

            Spacer()
            Button("Terminé") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    /// Count of catalog entries that pass the heuristic but ignore the search
    /// field — used to report "masqué par le filtre" honestly.
    private func filteredIDsCount(applyingSearch: Bool) -> Int {
        allModelIDs.filter { id in
            let passesHeuristic = showAll || ModelHeuristic.isLikelyChatModel(id: id, provider: provider)
            let passesSearch = !applyingSearch || search.isEmpty || id.localizedCaseInsensitiveContains(search)
            return passesHeuristic && passesSearch
        }.count
    }
}
