import Foundation
import Observation

/// Drives one run of a JavaScript agent and surfaces its progress to the UI:
/// the `host.log(...)` lines as they arrive, then the final result or error.
@Observable
@MainActor
final class AgentRunner {
    enum State: Equatable { case idle, running, finished, failed }

    private(set) var state: State = .idle
    private(set) var lines: [String] = []
    private(set) var result: String?
    private(set) var errorMessage: String?

    var isRunning: Bool { state == .running }

    func run(
        _ agent: AgentScript,
        input: String,
        settings: AppSettings,
        fileSpaces: FileSpaceStore,
        memory: MemoryStore,
        plugins: PluginStore,
        wiki: WikiManager
    ) {
        guard state != .running else { return }
        state = .running
        lines = []
        result = nil
        errorMessage = nil

        // Build the provider and tool registry on the main actor (they read
        // observable settings/stores), then capture the concrete, Sendable
        // values for the agent's host bridge.
        let tools = Self.buildTools(
            settings: settings, fileSpaces: fileSpaces,
            memory: memory, plugins: plugins, wiki: wiki)
        let provider = ProviderFactory.make(from: settings, tools: tools)
        let inputValue = Self.parseInput(input)

        let sink: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor in self?.lines.append(line) }
        }
        let runtime = AgentRuntime(
            makeProvider: { provider }, tools: tools, memory: memory, log: sink)
        let source = agent.source

        Task {
            do {
                let output = try await runtime.run(script: source, input: inputValue, timeout: 120)
                result = output
                state = .finished
            } catch {
                errorMessage = error.localizedDescription
                state = .failed
            }
        }
    }

    /// The input box accepts JSON (object/array/number/etc.) or, failing that,
    /// plain text passed through as a string. Empty input becomes `null`.
    private static func parseInput(_ text: String) -> Any {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return NSNull() }
        if let data = trimmed.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return value
        }
        return trimmed
    }

    /// Same registry the live chat builds (built-ins honouring tool toggles +
    /// installed HTTP plugins), so an agent sees exactly the user's tools.
    private static func buildTools(
        settings: AppSettings,
        fileSpaces: FileSpaceStore,
        memory: MemoryStore,
        plugins: PluginStore,
        wiki: WikiManager
    ) -> ToolRegistry {
        let isApple = settings.selectedProviderID == "apple"
        let isEnabled: (String) -> Bool = { name in
            isApple ? settings.isAppleToolEnabled(name) : settings.isToolEnabled(name)
        }
        let builtins = ToolCatalog.allTools(
            roots: fileSpaces.authorizedRoots,
            memory: memory,
            braveAPIKey: settings.braveAPIKey,
            wikiContext: wiki.state.context
        ).filter { isEnabled($0.spec.name) }
        let pluginTools = plugins.tools().filter { isEnabled($0.spec.name) }
        return ToolRegistry(tools: builtins + pluginTools)
    }
}
