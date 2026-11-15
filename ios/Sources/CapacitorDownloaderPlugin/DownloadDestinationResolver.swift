import Foundation

enum DownloadDestinationResolver {
    static func resolveDestinationURL(
        destination: String?,
        id: String,
        documentsDirectory: URL
    ) -> URL? {
        let trimmedDestination = destination?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let destination = trimmedDestination, !destination.isEmpty else {
            return documentsDirectory.appendingPathComponent(id)
        }

        if destination.hasPrefix("file://"), let url = URL(string: destination) {
            return url
        }

        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination)
        }

        if destination.hasPrefix("files/") || destination.hasPrefix("cache/") || destination.hasPrefix("private/") {
            guard let privateURL = resolvePrivateRelativeDestination(destination, fallbackId: id, documentsDirectory: documentsDirectory) else {
                return nil
            }
            return privateURL
        }

        return documentsDirectory.appendingPathComponent(destination)
    }

    /// Optional roots: `files/` and `cache/` stay under Documents (8.7.0). `private/` is iOS-only under Application Support.
    static func resolvePrivateRelativeDestination(_ destination: String, fallbackId: String, documentsDirectory: URL) -> URL? {
        if destination.hasPrefix("files/") {
            let relative = String(destination.dropFirst("files/".count))
            let path = relative.isEmpty ? fallbackId : relative
            guard !path.isEmpty else {
                return nil
            }
            return childURL(base: documentsDirectory.appendingPathComponent("files", isDirectory: true), relative: path)
        }

        if destination.hasPrefix("cache/") {
            let relative = String(destination.dropFirst("cache/".count))
            let path = relative.isEmpty ? fallbackId : relative
            guard !path.isEmpty else {
                return nil
            }
            return childURL(base: documentsDirectory.appendingPathComponent("cache", isDirectory: true), relative: path)
        }

        if destination.hasPrefix("private/") {
            let relative = String(destination.dropFirst("private/".count))
            guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            let privateRoot = base.appendingPathComponent("CapacitorDownloader", isDirectory: true)
            let path = relative.isEmpty ? fallbackId : relative
            guard !path.isEmpty else {
                return nil
            }
            return childURL(base: privateRoot, relative: path)
        }

        return nil
    }

    static func childURL(base: URL, relative: String) -> URL? {
        let trimmed = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let candidate = base.appendingPathComponent(trimmed)
        return candidate
    }
}