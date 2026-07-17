import SwiftUI
import TyKaozKit

/// Settings pane for prompt dictation: engine choice (Apple system
/// dictation vs local Parakeet V3) and per-engine model installation.
struct DictationSettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var appleAssetsInstalled: Bool?
    @State private var appleInstalling = false
    @State private var parakeetInstalled = ParakeetASR.isInstalled
    @State private var parakeetProgress: Double?
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Moteur de transcription") {
                Picker("Moteur", selection: $settings.transcriptionEngineID) {
                    Text("Apple").tag("apple")
                    Text("Parakeet V3").tag("parakeet")
                }
                .pickerStyle(.segmented)

                Text("""
                Les deux moteurs transcrivent en direct pendant que vous \
                parlez et fonctionnent sans réseau une fois leur modèle \
                téléchargé. Apple utilise la dictée système ; Parakeet V3 \
                (NVIDIA) est multilingue et tourne sur le Neural Engine, \
                avec un texte affiné à l'arrêt du micro.
                """)
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
            }

            Section("Apple — dictée système") {
                switch appleAssetsInstalled {
                case nil:
                    statusRow(color: .gray, text: "Vérification du modèle…")
                case true?:
                    statusRow(color: .green, text: "Modèle de langue installé.")
                case false?:
                    statusRow(color: .gray, text: "Modèle de langue non installé.")
                    if appleInstalling {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Téléchargement du modèle système…")
                                .font(Brand.Fonts.body(12))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Télécharger le modèle") { installAppleAssets() }
                    }
                }
            }

            Section("Parakeet V3") {
                if parakeetInstalled {
                    statusRow(color: .green, text: "Modèle installé.")
                } else if let parakeetProgress {
                    ProgressView(value: parakeetProgress) {
                        Text("Téléchargement… \(Int(parakeetProgress * 100)) %")
                            .font(Brand.Fonts.body(12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    statusRow(color: .gray, text: "Modèle non téléchargé.")
                    Button("Télécharger (~1 Go)") { downloadParakeet() }
                    Text("nvidia/parakeet-tdt-0.6b-v3 converti CoreML (FluidAudio), 25 langues dont le français. Licence Apache 2.0.")
                        .font(Brand.Fonts.body(11))
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(Brand.Colors.ember)
            }
        }
        .formStyle(.grouped)
        .task {
            appleAssetsInstalled = await AppleTranscriptionEngine.assetsInstalled()
        }
    }

    private func statusRow(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(.secondary)
        }
    }

    private func installAppleAssets() {
        appleInstalling = true
        errorMessage = nil
        Task {
            do {
                try await AppleTranscriptionEngine.installAssets()
                appleAssetsInstalled = await AppleTranscriptionEngine.assetsInstalled()
            } catch {
                errorMessage = "Téléchargement impossible : \(error.localizedDescription)"
            }
            appleInstalling = false
        }
    }

    private func downloadParakeet() {
        parakeetProgress = 0
        errorMessage = nil
        Task {
            do {
                try await ParakeetASR.download { fraction in
                    Task { @MainActor in parakeetProgress = fraction }
                }
                parakeetInstalled = ParakeetASR.isInstalled
            } catch {
                errorMessage = "Téléchargement impossible : \(error.localizedDescription)"
            }
            parakeetProgress = nil
        }
    }
}
