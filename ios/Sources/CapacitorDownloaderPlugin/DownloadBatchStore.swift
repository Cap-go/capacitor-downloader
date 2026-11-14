import Foundation

final class DownloadBatchStore {
    static let shared = DownloadBatchStore()

    static let userDefaultsKey = "CapacitorDownloaderBatches"

    struct Record: Codable {
        let batchId: String
        let generation: UInt64
        let fileCount: Int
        let fileProgress: [Float]
        let fileCompleted: [Bool]
        let completedCount: Int
        let failed: Bool
        let cancelled: Bool
        let paused: Bool
        let childTaskIds: [String]
        let savedDestinations: [Int: String]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ batches: [String: Record]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(batches) else {
            return
        }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    func load() -> [String: Record] {
        guard let data = defaults.data(forKey: Self.userDefaultsKey) else {
            return [:]
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode([String: Record].self, from: data)) ?? [:]
    }

    func clear() {
        defaults.removeObject(forKey: Self.userDefaultsKey)
    }
}
