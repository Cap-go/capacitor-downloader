import XCTest
@testable import CapacitorDownloaderPlugin

final class DownloadHttpErrorTaskGenerationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DownloadSessionDelegateTestSupport.reset()
    }

    override func tearDown() {
        DownloadSessionDelegateTestSupport.reset()
        for (key, _) in DownloadTaskGenerationStore.shared.allGenerations() {
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            if parts.count == 2, let taskId = Int(parts[1]) {
                let sessionId = String(parts[0])
                DownloadTaskGenerationStore.shared.removeGeneration(
                    forSessionIdentifier: sessionId,
                    taskIdentifier: taskId
                )
            }
        }
        super.tearDown()
    }

    func testHttp404ClearsTaskGenerationAfterDelegateCompletion() throws {
        try assertHttpStatusClearsTaskGeneration(statusCode: 404)
    }

    func testHttp500ClearsTaskGenerationAfterDelegateCompletion() throws {
        try assertHttpStatusClearsTaskGeneration(statusCode: 500)
    }

    private func assertHttpStatusClearsTaskGeneration(statusCode: Int) throws {
        let plugin = CapacitorDownloaderPlugin()
        plugin.load()
        let session = plugin.mainBackgroundSessionForTests
        let downloadId = "http-error-\(statusCode)"
        let task = session.downloadTask(with: URL(string: "https://example.invalid/\(downloadId)")!)
        task.taskDescription = downloadId

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapacitorDownloaderHttp-\(UUID().uuidString)")
        try Data("error-body".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let responseURL = URL(string: "https://example.invalid/\(downloadId)")!
        let httpResponse = HTTPURLResponse(
            url: responseURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        DownloadSessionDelegateTestSupport.httpResponseOverrides[task.taskIdentifier] = httpResponse

        let storageKey = DownloadTaskGenerationKey.storageKey(session: session, task: task)
        plugin.registerSingleDownloadForTests(
            downloadId: downloadId,
            task: task,
            session: session,
            generation: 7,
            destination: "files/http-error.bin"
        )
        XCTAssertTrue(plugin.registeredTaskGenerationKeysForTests().contains(storageKey))

        plugin.urlSession(session, downloadTask: task, didFinishDownloadingTo: tempURL)
        plugin.urlSession(session, task: task, didCompleteWithError: nil)

        XCTAssertFalse(plugin.registeredTaskGenerationKeysForTests().contains(storageKey))
        XCTAssertNil(DownloadTaskGenerationStore.shared.allGenerations()[storageKey])
    }
}