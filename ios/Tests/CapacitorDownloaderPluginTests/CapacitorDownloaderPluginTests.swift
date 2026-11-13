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
        store.setText("  Finished  ", for: "task-1", generation: 1)

        XCTAssertEqual(store.takeText(for: "task-1", generation: 1), "Finished")
        XCTAssertNil(store.takeText(for: "task-1", generation: 1))
    }

    func testRemoveText() {
        store.setText("Done", for: "task-1", generation: 1)
        store.removeText(for: "task-1", generation: 1)
        XCTAssertNil(store.takeText(for: "task-1", generation: 1))
    }

    func testGenerationMismatchLeavesStoredText() {
        store.setText("New", for: "task-1", generation: 2)
        store.removeText(for: "task-1", generation: 1)
        XCTAssertEqual(store.takeText(for: "task-1", generation: 2), "New")
    }

    func testTakeTextWithoutTaskGenerationUsesStoredEntry() {
        store.setText("Ready", for: "task-1", generation: 3)
        XCTAssertEqual(store.takeText(for: "task-1", generation: nil), "Ready")
    }

    func testConcurrentUpdatesDoNotDropEntries() {
        let ids = (0..<50).map { "task-\($0)" }
        DispatchQueue.concurrentPerform(iterations: ids.count) { index in
            store.setText("Body \(index)", for: ids[index], generation: 1)
        }

        for (index, id) in ids.enumerated() {
            XCTAssertEqual(store.takeText(for: id, generation: 1), "Body \(index)")
        }
    }
}

final class DownloadIdGenerationStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: DownloadIdGenerationStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CapacitorDownloaderIdGenerationTests")!
        defaults.removePersistentDomain(forName: "CapacitorDownloaderIdGenerationTests")
        store = DownloadIdGenerationStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "CapacitorDownloaderIdGenerationTests")
        super.tearDown()
    }

    func testPersistedGenerationSurvivesRelaunch() {
        store.setGeneration(3, forDownloadId: "episode-12")
        let restored = DownloadIdGenerationStore(defaults: defaults)
        XCTAssertEqual(restored.allGenerations()["episode-12"], 3)
        let next = (restored.allGenerations()["episode-12"] ?? 0) &+ 1
        XCTAssertEqual(next, 4)
    }

    func testNextGenerationAfterRelaunchDoesNotReuseStoredValue() {
        store.setGeneration(1, forDownloadId: "shared-id")
        let relaunched = DownloadIdGenerationStore(defaults: defaults)
        let generations = relaunched.allGenerations()
        let next = (generations["shared-id"] ?? 0) &+ 1
        XCTAssertEqual(next, 2)
    }
}

final class DownloadTaskGenerationStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: DownloadTaskGenerationStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CapacitorDownloaderTaskGenerationTests")!
        defaults.removePersistentDomain(forName: "CapacitorDownloaderTaskGenerationTests")
        store = DownloadTaskGenerationStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "CapacitorDownloaderTaskGenerationTests")
        super.tearDown()
    }

    func testPersistAndRestoreGeneration() {
        store.setGeneration(7, forTaskIdentifier: 42)
        XCTAssertEqual(store.allGenerations()[42], 7)
        store.removeGeneration(forTaskIdentifier: 42)
        XCTAssertNil(store.allGenerations()[42])
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
