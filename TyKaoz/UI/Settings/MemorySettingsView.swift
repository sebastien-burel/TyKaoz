import SwiftUI

/// Shows what the assistant has remembered and lets the user delete entries.
/// Important for a privacy-first app: the user stays in control of long-term
/// stored context.
struct MemorySettingsView: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if store.memories.isEmpty {
                    emptyState
                } else {
                    memoryList
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Brand.Colors.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mémoire")
                .font(Brand.Fonts.title(20))
                .foregroundStyle(Brand.Colors.ink)
            Text("""
            Ce dont l'assistant se souvient d'une conversation à l'autre. Ces \
            notes sont ajoutées au contexte des nouveaux messages. Vous pouvez \
            en supprimer à tout moment.
            """)
                .font(Brand.Fonts.body(12))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        Text("Aucune mémoire enregistrée.")
            .font(Brand.Fonts.body(13))
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    private var memoryList: some View {
        VStack(spacing: 0) {
            ForEach(store.memories) { memory in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(memory.title)
                            .font(Brand.Fonts.body(13))
                            .foregroundStyle(Brand.Colors.ink)
                        Text(memory.content)
                            .font(Brand.Fonts.body(12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    Button(role: .destructive) {
                        store.delete(id: memory.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Oublier cette mémoire")
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
    }
}
