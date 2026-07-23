import SwiftUI
import KaozKit

/// Settings for the ComfyUI image-generation provider. The user gives a
/// server URL (and optional key), then pastes one or more named workflows
/// (ComfyUI API-format JSON) each carrying a `%prompt%` marker where the
/// chat message should be injected. Each workflow becomes a selectable
/// "model".
struct ComfyUISettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var reach: ReachState = .idle
    @State private var newName = ""
    @State private var newJSON = ""
    @State private var addError: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Serveur") {
                TextField(
                    "URL",
                    text: $settings.comfyuiBaseURLString,
                    prompt: Text("http://localhost:8188")
                )
                .font(Brand.Fonts.mono(12))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await test() } }

                Text("URL de ton serveur ComfyUI, sans chemin.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }

            Section("Clé API (optionnelle)") {
                SecureField(
                    "Bearer token",
                    text: $settings.comfyuiAPIKey,
                    prompt: Text("Laisser vide pour un serveur sans auth")
                )
                .font(Brand.Fonts.mono(12))
                .textFieldStyle(.roundedBorder)

                Text("Stockée dans le trousseau macOS.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Tester la connexion") {
                        Task { await test() }
                    }
                    .disabled(settings.comfyuiBaseURL == nil || reach.isLoading)
                    reachStatus
                }
            }

            Section("Workflows") {
                if settings.comfyuiWorkflows.isEmpty {
                    Text("""
                    Aucun workflow. Colle ci-dessous un workflow ComfyUI \
                    (format API) contenant le marqueur \(ComfyUIClient.promptPlaceholder) \
                    là où le prompt doit être injecté.
                    """)
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.comfyuiWorkflows.keys.sorted(), id: \.self) { name in
                        ComfyWorkflowRow(name: name, json: settings.comfyuiWorkflows[name] ?? "")
                    }
                }
            }

            Section("Ajouter un workflow") {
                TextField("Nom", text: $newName, prompt: Text("flux2-720p"))
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $newJSON)
                    .font(Brand.Fonts.mono(11))
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Brand.Colors.slate.opacity(0.2), lineWidth: 1)
                    )

                if let addError {
                    Label(addError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(Brand.Fonts.body(11))
                }

                Button("Ajouter le workflow") { addWorkflow() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newJSON.isEmpty)
            }

            Section {
                UseAsActiveButton(providerID: .comfyui)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private func addWorkflow() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { addError = "Nom vide."; return }
        guard newJSON.contains(ComfyUIClient.promptPlaceholder) else {
            addError = "Le workflow doit contenir le marqueur \(ComfyUIClient.promptPlaceholder)."
            return
        }
        guard (try? JSONSerialization.jsonObject(with: Data(newJSON.utf8))) is [String: Any] else {
            addError = "JSON invalide (format API ComfyUI attendu)."
            return
        }
        settings.addComfyUIWorkflow(name: name, json: newJSON)
        newName = ""
        newJSON = ""
        addError = nil
    }

    private func test() async {
        guard let url = settings.comfyuiBaseURL else {
            reach = .failed("URL invalide.")
            return
        }
        reach = .loading
        let client = ComfyUIClient(baseURL: url, apiKey: settings.comfyuiAPIKey)
        reach = await client.systemStatsReachable()
            ? .ok
            : .failed("Serveur injoignable.")
    }

    // MARK: - Reachability status

    private enum ReachState {
        case idle, loading, ok, failed(String)

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    @ViewBuilder
    private var reachStatus: some View {
        switch reach {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView().controlSize(.small)
        case .ok:
            Label("Serveur joignable", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(Brand.Fonts.body(12))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(Brand.Fonts.body(12))
                .lineLimit(2)
        }
    }
}

/// One workflow, expandable to reveal the parameters it exposes via `%name%`
/// markers. `seed` gets a random/fixed toggle; other markers are plain
/// value fields pre-filled with their inline default.
private struct ComfyWorkflowRow: View {
    @Environment(AppSettings.self) private var settings
    let name: String
    let json: String

    var body: some View {
        DisclosureGroup {
            let parameters = ComfyUIClient.discoverParameters(in: json)
            if parameters.isEmpty {
                Text("Aucun paramètre. Ajoute des marqueurs comme %guidance=2.5% dans le workflow.")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(parameters, id: \.name) { parameter in
                    if parameter.name == "seed" {
                        seedControls
                    } else {
                        HStack {
                            Text(parameter.name)
                                .font(Brand.Fonts.mono(12))
                            Spacer()
                            TextField(
                                parameter.default,
                                text: valueBinding(parameter.name, default: parameter.default)
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundStyle(Brand.Colors.tide)
                Text(name)
                    .font(Brand.Fonts.body(13))
                Spacer()
                Button(role: .destructive) {
                    settings.removeComfyUIWorkflow(name: name)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Supprimer ce workflow")
            }
        }
    }

    @ViewBuilder
    private var seedControls: some View {
        Toggle("Seed aléatoire à chaque génération", isOn: seedRandom)
            .font(Brand.Fonts.body(12))
        if !seedRandom.wrappedValue {
            HStack {
                Text("seed")
                    .font(Brand.Fonts.mono(12))
                Spacer()
                TextField("0", text: valueBinding("seed", default: ""))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// Random when no `seed` value is stored; a fixed "0" placeholder when off.
    private var seedRandom: Binding<Bool> {
        Binding(
            get: { (settings.comfyuiWorkflowParams[name]?["seed"] ?? "").isEmpty },
            set: { random in settings.setComfyuiParam(random ? "" : "0", name: "seed", for: name) }
        )
    }

    private func valueBinding(_ parameter: String, default def: String) -> Binding<String> {
        Binding(
            get: { settings.comfyuiWorkflowParams[name]?[parameter] ?? def },
            set: { settings.setComfyuiParam($0, name: parameter, for: name) }
        )
    }
}
