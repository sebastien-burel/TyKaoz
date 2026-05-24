import SwiftUI

struct SettingsPanelView: View {
    @State private var serverURL: String = "http://localhost:11434"
    @State private var selectedModel: String = "llama3.2"

    private let mockModels = ["llama3.2", "qwen2.5:7b", "mistral:7b"]

    var body: some View {
        Form {
            Section("Serveur Ollama") {
                TextField("URL", text: $serverURL, prompt: Text("http://host:port"))
                    .font(Brand.Fonts.mono(12))
                    .textFieldStyle(.roundedBorder)
            }

            Section("Modèle") {
                Picker("Modèle", selection: $selectedModel) {
                    ForEach(mockModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 240)
    }
}

#Preview {
    SettingsPanelView()
}
