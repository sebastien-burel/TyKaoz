import SwiftUI
import TyKaozKit
import GRDB

/// Three-section diagnostic view backed by `Lint.run`. Each row
/// carries an actionable button so the agent's mess can be cleaned
/// up by humans in the browser — dangling link → jump to the source,
/// missing concept → seed a stub page the user can flesh out.
struct WikiLintView: View {
    let context: WikiContext
    /// Bound to the browser's selection — used to navigate to a
    /// source page when the user clicks a dangling-link row.
    @Binding var selection: WikiPageRef?

    @Environment(WikiManager.self) private var wiki

    @State private var report: LintReport?
    @State private var loading = false
    @State private var error: String?
    @State private var auditPromptCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let error {
                    Text(error)
                        .font(Brand.Fonts.body(12))
                        .foregroundStyle(.red)
                } else if let report {
                    orphansSection(report.orphans)
                    danglingSection(report.danglingLinks)
                    missingSection(report.missingConcepts)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Brand.Colors.paper)
        .task(id: wiki.indexRevision) { await reload() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Audit du wiki")
                .font(Brand.Fonts.title(22))
                .foregroundStyle(Brand.Colors.ink)
            Text("Vue déterministe : orphelins, liens pendouillants, concepts manquants.")
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Audit LLM…") { copyAuditPrompt() }
                    .disabled(report == nil)
                if auditPromptCopied {
                    Label("Prompt copié — colle-le dans une conversation.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(Brand.Fonts.body(11))
                }
            }
            .padding(.top, 6)
        }
    }

    /// Semantic half of the lint: builds a prompt embedding the SQL
    /// findings and copies it to the clipboard. The user pastes it into
    /// any conversation so fixes run through the visible chat loop —
    /// nothing is auto-applied.
    private func copyAuditPrompt() {
        guard let report else { return }
        let prompt = WikiLintPrompt.build(report: report)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        WikiLog.append(op: "lint", detail: "audit LLM préparé", in: context.wikiRoot)
        auditPromptCopied = true
    }

    // MARK: - Orphans

    private func orphansSection(_ orphans: [LintReport.Orphan]) -> some View {
        Section(
            title: "Orphelins",
            count: orphans.count,
            emptyLabel: "Aucune page sans lien entrant."
        ) {
            ForEach(orphans, id: \.pageID) { o in
                HStack(spacing: 8) {
                    pageBadge(title: o.title, id: o.pageID)
                    Spacer()
                    Button("Ouvrir") {
                        Task { await selectPage(id: o.pageID) }
                    }
                    .buttonStyle(.borderless)
                    .font(Brand.Fonts.body(12))
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Dangling

    private func danglingSection(_ dangling: [LintReport.DanglingLink]) -> some View {
        Section(
            title: "Liens pendouillants",
            count: dangling.count,
            emptyLabel: "Aucun lien sans cible."
        ) {
            ForEach(Array(dangling.enumerated()), id: \.offset) { _, link in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.srcTitle)
                            .font(Brand.Fonts.body(12))
                            .foregroundStyle(Brand.Colors.ink)
                        Text("→ [[\(link.dstTitleRaw)]]")
                            .font(Brand.Fonts.mono(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Corriger") {
                        Task { await selectPage(id: link.srcPageID) }
                    }
                    .buttonStyle(.borderless)
                    .font(Brand.Fonts.body(12))
                    .help("Ouvre la page source pour modifier le lien.")
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Missing concepts

    private func missingSection(_ missing: [LintReport.MissingConcept]) -> some View {
        Section(
            title: "Concepts manquants",
            count: missing.count,
            emptyLabel: "Aucun concept récurrent sans page."
        ) {
            ForEach(missing, id: \.titleRaw) { concept in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(concept.titleRaw)
                            .font(Brand.Fonts.body(12))
                            .foregroundStyle(Brand.Colors.ink)
                        Text("\(concept.references) référence\(concept.references == 1 ? "" : "s")")
                            .font(Brand.Fonts.body(10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Créer la page") {
                        Task { await createMissing(title: concept.titleRaw) }
                    }
                    .buttonStyle(.borderless)
                    .font(Brand.Fonts.body(12))
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            let r = try await context.pool.read { db in try Lint.run(db) }
            report = r
            error = nil
        } catch let e {
            error = e.localizedDescription
            report = nil
        }
    }

    @MainActor
    private func selectPage(id: String) async {
        let ref: WikiPageRef? = try? await context.pool.read { db in
            try Row.fetchOne(db, sql: """
                SELECT id, title, path FROM pages WHERE id = ?;
            """, arguments: [id]).map {
                WikiPageRef(id: $0["id"], title: $0["title"], path: $0["path"])
            }
        }
        if let ref { selection = ref }
    }

    /// Creates a stub `.md` for a missing concept and selects it.
    /// The file-watcher picks the new file up and re-indexes; the
    /// pre-existing dangling links promote to resolved.
    @MainActor
    private func createMissing(title: String) async {
        let slug = Self.slugify(title)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let today = formatter.string(from: .now)
        let content = """
        ---
        id: \(slug)
        title: \(title)
        created: \(today)
        updated: \(today)
        ---

        # \(title)

        À compléter.
        """
        let url = context.wikiRoot.appendingPathComponent("\(slug).md")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            // Force a reindex so the new row appears in the sidebar
            // immediately (file-watcher would catch it too, but this
            // avoids a perceived lag).
            await wiki.reindexNow()
            await selectPage(id: slug)
            await reload()
        } catch let e {
            error = e.localizedDescription
        }
    }

    /// Delegates to the shared `Slug` (Core/Wiki) — kept as an alias so
    /// existing call sites and tests stay valid.
    static func slugify(_ raw: String) -> String {
        Slug.make(raw)
    }
}

// MARK: - Section helper

private struct Section<Content: View>: View {
    let title: String
    let count: Int
    let emptyLabel: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(Brand.Fonts.body(14).bold())
                    .foregroundStyle(Brand.Colors.ink)
                Text("(\(count))")
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
            }
            if count == 0 {
                Text(emptyLabel)
                    .font(Brand.Fonts.body(11))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Brand.Colors.slate.opacity(0.12), lineWidth: 1)
                        )
                )
            }
        }
    }
}

private extension WikiLintView {
    func pageBadge(title: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Brand.Fonts.body(12)).foregroundStyle(Brand.Colors.ink)
            Text("id: \(id)").font(Brand.Fonts.mono(10)).foregroundStyle(.secondary)
        }
    }
}
