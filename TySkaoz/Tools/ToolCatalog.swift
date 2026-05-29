import Foundation

/// Single source of truth for the built-in tools. ContentView builds the live
/// registry from here; the settings UI reads the same name list to offer
/// per-tool toggles. Keeping construction in one place avoids the two drifting
/// apart.
enum ToolCatalog {
    /// Canonical, ordered list of every built-in tool name. Drives the
    /// settings toggles without needing to instantiate tools (which require
    /// runtime stores).
    static let allToolNames: [String] = [
        "current_datetime",
        "fetch_url",
        "list_directory",
        "read_file",
        "grep_files",
        "save_memory",
        "list_memories",
        "read_memory"
    ]

    /// Every built-in tool, bound to the current authorised folders and the
    /// memory store.
    @MainActor
    static func allTools(roots: [AuthorizedRoot], memory: MemoryStore) -> [any Tool] {
        [
            CurrentDateTimeTool(),
            FetchURLTool(),
            ListDirectoryTool(roots: roots),
            ReadFileTool(roots: roots),
            GrepFilesTool(roots: roots),
            SaveMemoryTool(store: memory),
            ListMemoriesTool(store: memory),
            ReadMemoryTool(store: memory)
        ]
    }

    /// The tools the user has left enabled, ready to hand to a provider.
    @MainActor
    static func enabledTools(
        roots: [AuthorizedRoot],
        memory: MemoryStore,
        settings: AppSettings
    ) -> [any Tool] {
        allTools(roots: roots, memory: memory)
            .filter { settings.isToolEnabled($0.spec.name) }
    }

    /// Short French label shown in the settings list.
    static func label(for name: String) -> String {
        switch name {
        case "current_datetime": return "Date et heure"
        case "fetch_url":        return "Récupérer une page web"
        case "list_directory":   return "Lister un dossier"
        case "read_file":        return "Lire un fichier"
        case "grep_files":       return "Rechercher dans les fichiers"
        case "save_memory":      return "Enregistrer en mémoire"
        case "list_memories":    return "Lister les mémoires"
        case "read_memory":      return "Lire une mémoire"
        default:                 return name
        }
    }
}
