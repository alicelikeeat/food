import Foundation

/// 把进行中的会话存成一个本地 JSON 文件。每次状态变化都原子写入，杀进程后可恢复。
final class SessionStore {
    private let url: URL

    init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("cooking-session.json")
    }

    func load() -> CookingSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CookingSession.self, from: data)
    }

    /// 只有未完成的会话才值得「继续做菜」。
    func loadUnfinished(recipeID: String) -> CookingSession? {
        guard let session = load(), session.recipeID == recipeID, !session.isFinished else { return nil }
        return session
    }

    func save(_ session: CookingSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// 每道菜一句做法备注。
final class NoteStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func note(for recipeID: String) -> String? {
        let value = defaults.string(forKey: key(recipeID))
        return (value?.isEmpty ?? true) ? nil : value
    }

    func setNote(_ note: String, for recipeID: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key(recipeID))
        } else {
            defaults.set(trimmed, forKey: key(recipeID))
        }
    }

    private func key(_ recipeID: String) -> String { "note.\(recipeID)" }
}

enum SettingsKey {
    static let muted = "settings.muted"
    static let voiceConfirm = "settings.voiceConfirm"
    static let cameraOff = "settings.cameraOff"
    /// 测试用短计时。也可用启动参数 `-settings.shortTimers YES` 打开。
    static let shortTimers = "settings.shortTimers"
}
