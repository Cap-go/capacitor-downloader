import XCTest
@testable import CapacitorDownloaderPlugin

final class DownloadDestinationResolverTests: XCTestCase {
    private let documentsDirectory = URL(fileURLWithPath: "/var/mobile/Documents")

    func testEmptyDestinationFallsBackToDocumentsPlusId() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: nil,
            id: "download-1",
            documentsDirectory: documentsDirectory
        )

        XCTAssertEqual(url, documentsDirectory.appendingPathComponent("download-1"))
    }

    func testBlankDestinationFallsBackToDocumentsPlusId() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "   ",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )

        XCTAssertEqual(url, documentsDirectory.appendingPathComponent("download-1"))
    }

    func testRelativeDestinationUsesDocumentsDirectory() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "downloads/sample.zip",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )

        XCTAssertEqual(url, documentsDirectory.appendingPathComponent("downloads/sample.zip"))
    }

    func testAbsolutePathUsesFileURL() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "/tmp/custom-file.bin",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )

        XCTAssertEqual(url, URL(fileURLWithPath: "/tmp/custom-file.bin"))
    }

    func testFileURLDestinationIsUsedDirectly() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "file:///tmp/custom-file.bin",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )

        XCTAssertEqual(url, URL(string: "file:///tmp/custom-file.bin"))
    }
}

final class DownloadDestinationStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: DownloadDestinationStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CapacitorDownloaderPluginTests")!
        defaults.removePersistentDomain(forName: "CapacitorDownloaderPluginTests")
        store = DownloadDestinationStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "CapacitorDownloaderPluginTests")
        super.tearDown()
    }

    func testSetAndTakeDestination() {
        store.setDestination("downloads/file.zip", for: "task-1")

        XCTAssertEqual(store.takeDestination(for: "task-1"), "downloads/file.zip")
        XCTAssertNil(store.takeDestination(for: "task-1"))
    }

    func testRemoveDestination() {
        store.setDestination("downloads/file.zip", for: "task-1")

        store.removeDestination(for: "task-1")

        XCTAssertNil(store.takeDestination(for: "task-1"))
    }
}

final class DownloadCompletedNotificationTextTests: XCTestCase {
    func testNormalizeRejectsBlank() {
        XCTAssertNil(DownloadCompletedNotificationText.normalize(nil))
        XCTAssertNil(DownloadCompletedNotificationText.normalize(""))
        XCTAssertNil(DownloadCompletedNotificationText.normalize("  "))
    }

    func testNormalizeTrims() {
        XCTAssertEqual(DownloadCompletedNotificationText.normalize("  Ready  "), "Ready")
    }
}

final class DownloadCompletedNotificationStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: DownloadCompletedNotificationStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CapacitorDownloaderNotificationTests")!
        defaults.removePersistentDomain(forName: "CapacitorDownloaderNotificationTests")
        store = DownloadCompletedNotificationStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "CapacitorDownloaderNotificationTests")
        super.tearDown()
    }

    func testSetAndTakeText() {
        store.setText("  Finished  ", for: "task-1")

        XCTAssertEqual(store.takeText(for: "task-1"), "Finished")
        XCTAssertNil(store.takeText(for: "task-1"))
    }

    func testRemoveText() {
        store.setText("Done", for: "task-1")
        store.removeText(for: "task-1")
        XCTAssertNil(store.takeText(for: "task-1"))
    }

    func testConcurrentUpdatesDoNotDropEntries() {
        let ids = (0..<50).map { "task-\($0)" }
        DispatchQueue.concurrentPerform(iterations: ids.count) { index in
            store.setText("Body \(index)", for: ids[index])
        }

        for (index, id) in ids.enumerated() {
            XCTAssertEqual(store.takeText(for: id), "Body \(index)")
        }
    }
}

final class DownloadHTTPValidatorTests: XCTestCase {
    func testSuccessfulStatusCodes() {
        XCTAssertTrue(DownloadHTTPValidator.isSuccessfulStatusCode(200))
        XCTAssertTrue(DownloadHTTPValidator.isSuccessfulStatusCode(204))
        XCTAssertTrue(DownloadHTTPValidator.isSuccessfulStatusCode(299))
    }

    func testNonSuccessfulStatusCodesAreRejected() {
        XCTAssertFalse(DownloadHTTPValidator.isSuccessfulStatusCode(199))
        XCTAssertFalse(DownloadHTTPValidator.isSuccessfulStatusCode(404))
        XCTAssertFalse(DownloadHTTPValidator.isSuccessfulStatusCode(500))
    }
}
