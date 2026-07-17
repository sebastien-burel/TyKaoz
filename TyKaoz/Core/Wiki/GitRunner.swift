import Foundation
import TyKaozKit

/// Best-effort git wrapper for the wiki store. Decision Q2: every
/// `write_wiki_page` records a commit so the user has an audit log
/// they can `git log` / `git revert` / `git push` independently.
///
/// Failure modes are intentionally swallowed: if the host lacks
/// `/usr/bin/git`, or if app-sandbox refuses to launch it, the write
/// still goes through. We don't want a missing git to silently break
/// the agent's editing loop — versioning is a safety net, not a
/// hard dependency.
enum GitRunner {
    /// Initialises a repo at `root` if there isn't one yet, then
    /// stages `relativePath` and creates a commit with `message`.
    /// Returns true when a commit was actually created.
    @discardableResult
    static func commit(
        message: String,
        in root: URL,
        relativePath: String? = nil
    ) -> Bool {
        guard let git = findGitBinary() else { return false }

        // git init if needed.
        let dotGit = root.appendingPathComponent(".git", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dotGit.path) {
            guard runStatus(git: git, args: ["init", "--quiet"], cwd: root) == 0 else {
                return false
            }
            // Identity to keep `git commit` happy in CI / sandboxed contexts.
            _ = runStatus(git: git, args: ["config", "user.email", "agent@tykaoz.local"], cwd: root)
            _ = runStatus(git: git, args: ["config", "user.name", "TyKaoz Agent"], cwd: root)
        }

        let addArg = relativePath ?? "."
        guard runStatus(git: git, args: ["add", "--", addArg], cwd: root) == 0 else {
            return false
        }
        // `commit` exits non-zero when there's nothing to commit. We
        // treat that as a no-op success, not an error.
        let rc = runStatus(
            git: git,
            args: ["commit", "--quiet", "-m", message, "--allow-empty-message"],
            cwd: root
        )
        return rc == 0
    }

    // MARK: - Internals

    /// Returns the first path that exists and is executable, nil
    /// otherwise. Sandboxed apps may not have access even when the
    /// path exists.
    private static func findGitBinary() -> URL? {
        for path in ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"] {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func runStatus(git: URL, args: [String], cwd: URL) -> Int32 {
        let p = Process()
        p.executableURL = git
        p.arguments = args
        p.currentDirectoryURL = cwd
        // Capture output so failures don't pollute the test/app stdout.
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }
}
