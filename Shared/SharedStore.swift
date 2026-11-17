import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Persiste o snapshot no App Group para o Widget ler o mesmo dado do app.
enum SharedStore {
    static let appGroup = "group.com.andersonaires.musestats"
    private static let key = "museUsageSnapshot.v3"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func save(_ snapshot: UsageSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
        // Arquivo no container do grupo (quando o App Group está ativo nas capabilities).
        if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
           let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: dir.appendingPathComponent("snapshot.json"), options: .atomic)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func load() -> UsageSnapshot {
        if let data = defaults.data(forKey: key),
           let snap = try? JSONDecoder().decode(UsageSnapshot.self, from: data) {
            return snap
        }
        if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
           let data = try? Data(contentsOf: dir.appendingPathComponent("snapshot.json")),
           let snap = try? JSONDecoder().decode(UsageSnapshot.self, from: data) {
            return snap
        }
        return .demo
    }
}
