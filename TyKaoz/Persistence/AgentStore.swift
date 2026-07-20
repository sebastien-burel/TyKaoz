import Foundation
import Observation

/// A JavaScript agent the user can edit and run. Persisted so it survives
/// relaunches.
struct AgentScript: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var source: String

    init(id: UUID = UUID(), name: String, source: String) {
        self.id = id
        self.name = name
        self.source = source
    }
}

/// Owns the user's JavaScript agents, persisted as a single JSON file (mirrors
/// `PluginStore`). The agents are run by `AgentRuntime` from the Agents window.
@Observable
@MainActor
final class AgentStore {
    private(set) var agents: [AgentScript] = []

    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = AgentStore.defaultFileURL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        load()
    }

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support.appending(path: "TyKaoz/agents.json")
    }

    @discardableResult
    func add(name: String = "Nouvel agent", source: String = AgentStore.templateSource) -> AgentScript {
        let agent = AgentScript(name: name, source: source)
        agents.append(agent)
        save()
        return agent
    }

    func update(_ agent: AgentScript) {
        guard let index = agents.firstIndex(where: { $0.id == agent.id }) else { return }
        agents[index] = agent
        save()
    }

    func remove(id: UUID) {
        agents.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(agents) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AgentScript].self, from: data)
        else { return }
        agents = decoded
    }

    /// Starter script shown when creating a new agent — demonstrates the
    /// `host.*` surface available to an agent.
    nonisolated static let templateSource = """
    // Agent d'exemple. Définissez globalThis.run(input) ; sa valeur de retour
    // est le résultat de l'agent. API disponible :
    //   host.llm.chat(messages, onToken)  — pilote le modèle courant (streaming)
    //   host.tool.list() / host.tool.call(name, args)  — outils de TyKaoz
    //   host.memory.save(titre, contenu) / host.memory.list() / host.memory.read(id)
    //   host.log(...)  — affiche une ligne dans la console ci-dessous
    globalThis.run = async function (input) {
      host.log("Entrée :", JSON.stringify(input));

      const outils = (await host.tool.list()).map(function (t) { return t.name; });
      host.log("Outils disponibles :", outils.join(", "));

      const reponse = await host.llm.chat(
        [{ role: "user", content: "Dis bonjour en breton, en une phrase." }],
        function (delta) { /* tokens reçus au fil de l'eau */ }
      );
      host.log("Réponse du modèle :", reponse);

      return reponse;
    };
    """
}
