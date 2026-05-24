import Foundation

enum MockData {
    static let conversations: [Conversation] = [
        Conversation(
            title: "Exploration MLX",
            messages: [
                Message(role: .user, content: "Quels modèles MLX tournent confortablement sur 16 Go ?"),
                Message(role: .assistant, content: "Sur 16 Go, on vise les variantes 3B et 7B quantifiées (4-bit). Llama 3.2 3B et Qwen 2.5 7B Q4 passent bien.")
            ]
        ),
        Conversation(
            title: "Notes RAG en français",
            messages: [
                Message(role: .user, content: "Quel embedding pour du français juridique ?"),
                Message(role: .assistant, content: "bge-m3 ou multilingual-e5-large donnent de bons résultats. Pour du juridique, prévoir un fine-tuning sur du corpus métier.")
            ]
        ),
        Conversation(
            title: "Test API Ollama",
            messages: [
                Message(role: .user, content: "Ping ?"),
                Message(role: .assistant, content: "Pong.")
            ]
        )
    ]
}
