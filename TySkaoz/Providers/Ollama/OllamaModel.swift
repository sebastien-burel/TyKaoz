import Foundation

struct OllamaModel: Decodable, Identifiable, Hashable {
    let name: String
    let size: Int64
    let modifiedAt: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case modifiedAt = "modified_at"
    }
}

struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]
}
