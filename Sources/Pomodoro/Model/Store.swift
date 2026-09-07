import Foundation

/// Only the config and a single elapsed offset are stored. Phase, round, marks
/// and progress are all derivable from those two, so there is no second copy of
/// the truth to fall out of sync.
struct Saved: Codable {
    var v = 1
    var config: Config
    var elapsed: TimeInterval?
}

struct Store {
    static let key = "pomodoro.v1"   // bump the suffix if the shape above changes

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ saved: Saved) {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: Store.key)
    }

    func load() -> Saved? {
        guard let data = defaults.data(forKey: Store.key),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              saved.v == 1
        else { return nil }
        return saved
    }
}
