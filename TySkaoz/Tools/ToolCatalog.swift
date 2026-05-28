import Foundation

/// Single source of truth for the built-in tools. ContentView builds the live
/// registry from here; the settings UI reads the same list to offer per-tool
/// toggles. Keeping construction in one place avoids the two drifting apart.
enum ToolCatalog {
    /// Every built-in tool, bound to the current authorised folders.
    @MainActor
    static func allTools(roots: [AuthorizedRoot]) -> [any Tool] {
        [
            CurrentDateTimeTool(),
            FetchURLTool(),
            ListDirectoryTool(roots: roots),
            ReadFileTool(roots: roots),
            GrepFilesTool(roots: roots)
        ]
    }

    /// The tools the user has left enabled, ready to hand to a provider.
    @MainActor
    static func enabledTools(roots: [AuthorizedRoot], settings: AppSettings) -> [any Tool] {
        allTools(roots: roots).filter { settings.isToolEnabled($0.spec.name) }
    }

    /// Specs of every built-in tool (folder-independent), for listing in the
    /// settings UI.
    @MainActor
    static var allSpecs: [ToolSpec] {
        allTools(roots: []).map(\.spec)
    }

    /// Short French label shown in the settings list.
    static func label(for name: String) -> String {
        switch name {
        case "current_datetime": return "Date et heure"
        case "fetch_url":        return "Récupérer une page web"
        case "list_directory":   return "Lister un dossier"
        case "read_file":        return "Lire un fichier"
        case "grep_files":       return "Rechercher dans les fichiers"
        default:                 return name
        }
    }
}
