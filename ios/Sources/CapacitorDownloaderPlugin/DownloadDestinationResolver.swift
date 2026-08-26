import Foundation

enum DownloadDestinationResolver {
    static func resolveDestinationURL(
        destination: String?,
        id: String,
        documentsDirectory: URL
    ) -> URL {
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

        return documentsDirectory.appendingPathComponent(destination)
    }
}
