import SwiftUI

/// Inline, collapsible card for a tool invocation. Collapsed it shows the tool
/// name and a status icon; expanded it reveals the JSON arguments and the
/// tool's result. The result is paired by `toolCallID` and may be nil while
/// the call is still running.
struct ToolCallCard: View {
    let call: Message
    let result: Message?

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                Divider().padding(.vertical, 6)
                details
            }
        }
        .padding(10)
        .background(Brand.Colors.slate.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Brand.Colors.slate.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.Colors.tide)
                Text(ToolCatalog.label(for: call.toolName ?? ""))
                    .font(Brand.Fonts.body(13))
                    .foregroundStyle(Brand.Colors.ink)
                statusIcon
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.Colors.slate.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let result {
            if result.toolIsError == true {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            section(title: "Arguments", body: prettyArguments)
            if let result {
                section(
                    title: result.toolIsError == true ? "Erreur" : "Résultat",
                    body: result.content.isEmpty ? "(vide)" : result.content
                )
            }
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Brand.Fonts.body(11))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.custom("JetBrains Mono", size: 11))
                .foregroundStyle(Brand.Colors.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Re-indents the stored JSON arguments for readability; falls back to the
    /// raw string if it isn't valid JSON.
    private var prettyArguments: String {
        let raw = call.content
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(data: pretty, encoding: .utf8)
        else { return raw.isEmpty ? "(aucun)" : raw }
        return string
    }
}
