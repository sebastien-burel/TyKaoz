import Foundation
import TyKaozKit
import CryptoKit

/// SHA-256 of a markdown page's canonical bytes. Stored on `pages.content_hash`
/// so the indexer can skip pages whose content hasn't changed.
///
/// "Canonical" here means: UTF-8 bytes of the raw text, no normalisation.
/// Whitespace, line endings, and frontmatter all participate — we want the
/// indexer to react to anything that affects how the page renders or links.
enum HashStore {
    /// Returns the lowercase 64-char hex digest of `text`'s UTF-8 bytes.
    static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
