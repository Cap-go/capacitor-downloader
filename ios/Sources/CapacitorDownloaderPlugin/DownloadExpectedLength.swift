import Foundation

enum DownloadExpectedLength {
    static func parsePositiveHeaderValue(_ raw: String?) -> Int64? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int64(trimmed), value > 0 else {
            return nil
        }
        return value
    }

    static func headerValue(in response: HTTPURLResponse, headerName: String) -> String? {
        let target = headerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            return nil
        }
        for (key, value) in response.allHeaderFields {
            guard let keyString = key as? String else {
                continue
            }
            if keyString.caseInsensitiveCompare(target) == .orderedSame {
                if let stringValue = value as? String {
                    return stringValue
                }
                return "\(value)"
            }
        }
        return nil
    }

    static func parse(from response: HTTPURLResponse, headerName: String) -> Int64? {
        parsePositiveHeaderValue(headerValue(in: response, headerName: headerName))
    }
}