import Foundation

/// 随包菜谱。字段与 Resources/*.json 一一对应。
struct Recipe: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let summary: String
    let servings: String
    let cookware: [String]
    let ingredients: [Ingredient]
    let steps: [RecipeStep]
}

struct Ingredient: Codable, Equatable, Identifiable {
    let name: String
    let amount: String
    var id: String { name }
}

struct RecipeStep: Codable, Equatable, Identifiable {
    /// 稳定 ID，用于会话恢复、通知 ID 和确认去重。
    let id: String
    let title: String
    let instruction: String
    let spoken: String
    /// 主按钮文案。计时步骤为 nil。
    let confirmLabel: String?
    let confirmPhrases: [String]
    let demo: DemoAsset
    let observation: ObservationTarget?
    let timer: TimerConfig?
}

struct DemoAsset: Codable, Equatable {
    let video: String
    let targetFrameSeconds: Double?
    let isPlaceholder: Bool
    let source: String
}

struct ObservationTarget: Codable, Equatable {
    let kind: String
    let fallbackHint: String
    let references: [ReferenceSwatch]
}

struct ReferenceSwatch: Codable, Equatable, Identifiable {
    /// 与 CaramelReading 的 rawValue 对应。
    let id: String
    let label: String
    let image: String
}

struct TimerConfig: Codable, Equatable {
    let seconds: Int
    let extendSeconds: Int
    /// 默认时长是否已经过实际试菜核定。
    let verified: Bool
    let checkPrompt: String
}

enum RecipeStore {
    static func loadBundled(named name: String = "hongshaorou", bundle: Bundle = .main) throws -> Recipe {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Recipe.self, from: Data(contentsOf: url))
    }

    static func mediaURL(_ fileName: String, bundle: Bundle = .main) -> URL? {
        let ns = fileName as NSString
        return bundle.url(forResource: ns.deletingPathExtension, withExtension: ns.pathExtension)
    }
}
