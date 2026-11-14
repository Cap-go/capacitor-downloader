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

    func testFilesPrefixUsesApplicationSupport() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "files/offline/map.zip",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            XCTFail("Missing application support directory")
            return
        }
        XCTAssertEqual(url, support.appendingPathComponent("offline/map.zip"))
    }

    func testCachePrefixUsesCachesDirectory() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "cache/temp.bin",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            XCTFail("Missing caches directory")
            return
        }
        XCTAssertEqual(url, caches.appendingPathComponent("temp.bin"))
    }

    func testPrivatePrefixUsesPluginSupportFolder() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "private/maps/tile.pack",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            XCTFail("Missing application support directory")
            return
        }
        let expected = support
            .appendingPathComponent("CapacitorDownloader", isDirectory: true)
            .appendingPathComponent("maps/tile.pack")
        XCTAssertEqual(url, expected)
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

final class DownloadBatchProgressTests: XCTestCase {
    private var batchDefaults: UserDefaults!

    override func setUp() {
        batchDefaults = UserDefaults(suiteName: "CapacitorDownloaderPluginTests.batch")!
        batchDefaults.removePersistentDomain(forName: "CapacitorDownloaderPluginTests.batch")
    }

    override func tearDown() {
        batchDefaults.removePersistentDomain(forName: "CapacitorDownloaderPluginTests.batch")
    }

    func testOverallProgressAveragesFiles() {
        let overall = DownloadBatchProgress.overallProgress(fileProgress: [1, 0.5, 0], fileCount: 3)
        XCTAssertEqual(overall, 0.5, accuracy: 0.0001)
    }

    func testBatchCancellationNeedsResolvedPathNotWhitespaceDestination() {
        let documents = URL(fileURLWithPath: "/var/mobile/Documents")
        let childId = "bundle#0"
        let whitespace = "   "
        let resolvedPath = DownloadDestinationResolver.resolveDestinationURL(
            destination: whitespace,
            id: childId,
            documentsDirectory: documents
        ).path

        let store = DownloadBatchStore(defaults: batchDefaults)
        let coordinator = DownloadBatchCoordinator(store: store)
        guard let generation = coordinator.startBatch(batchId: "bundle", fileCount: 1, singleDownloadIds: []) else {
            XCTFail("expected batch to start")
            return
        }

        coordinator.recordMovedDestination(batchId: "bundle", generation: generation, fileIndex: 0, destination: resolvedPath)
        XCTAssertEqual(coordinator.destinationsForCancellation(batchId: "bundle"), [resolvedPath])

        let mistakenCleanupTarget = DownloadDestinationResolver.resolveDestinationURL(
            destination: whitespace,
            id: "cleanup",
            documentsDirectory: documents
        ).path
        XCTAssertNotEqual(mistakenCleanupTarget, resolvedPath)

        coordinator.removeBatch(batchId: "bundle")
        store.clear()
    }

    func testLoadRestoresBackgroundTasksForMainAndWifiOnlySessions() {
        let plugin = CapacitorDownloaderPlugin()
        XCTAssertFalse(plugin.hasRegisteredTask(id: "restored-single"))

        let downloadTask = plugin.mainBackgroundSessionForTests.downloadTask(with: URL(string: "https://example.com/file.bin")!)
        downloadTask.taskDescription = "restored-single"
        downloadTask.resume()

        plugin.load()
        XCTAssertTrue(plugin.restoredBackgroundSessionIdentifiers.contains(DownloadSessionIdentifiers.main))
        XCTAssertTrue(plugin.restoredBackgroundSessionIdentifiers.contains(DownloadSessionIdentifiers.wifiOnly))
        XCTAssertTrue(plugin.hasRegisteredTask(id: "restored-single"))
    }

    func testStaleChildGenerationDoesNotFailActiveBatch() {
        let store = DownloadBatchStore(defaults: batchDefaults)
        let coordinator = DownloadBatchCoordinator(store: store)
        guard let firstGeneration = coordinator.startBatch(batchId: "bundle", fileCount: 1, singleDownloadIds: []) else {
            XCTFail("expected first batch")
            return
        }
        let staleTaskId = coordinator.fileTaskId(batchId: "bundle", generation: firstGeneration, fileIndex: 0)
        coordinator.registerChildTask(batchId: "bundle", taskId: staleTaskId, fileIndex: 0)
        coordinator.removeBatch(batchId: "bundle", unregisterChildren: false)

        guard let secondGeneration = coordinator.startBatch(batchId: "bundle", fileCount: 1, singleDownloadIds: []) else {
            XCTFail("expected second batch")
            return
        }
        XCTAssertNotEqual(firstGeneration, secondGeneration)
        XCTAssertNil(coordinator.activeChildParts(for: staleTaskId))
        XCTAssertFalse(coordinator.beginFailure(batchId: "bundle", generation: firstGeneration))
        XCTAssertTrue(coordinator.beginFailure(batchId: "bundle", generation: secondGeneration))
        coordinator.removeBatch(batchId: "bundle")
        store.clear()
    }

    func testBatchCoordinatorParsesRegisteredTaskId() {
        let store = DownloadBatchStore(defaults: batchDefaults)
        let coordinator = DownloadBatchCoordinator(store: store)
        guard let generation = coordinator.startBatch(batchId: "bundle", fileCount: 3, singleDownloadIds: []) else {
            XCTFail("expected batch to start")
            return
        }
        let taskId = coordinator.fileTaskId(batchId: "bundle", generation: generation, fileIndex: 2)
        coordinator.registerChildTask(batchId: "bundle", taskId: taskId, fileIndex: 2)
        let parts = coordinator.childParts(for: taskId)
        XCTAssertEqual(parts?.batchId, "bundle")
        XCTAssertEqual(parts?.generation, generation)
        XCTAssertEqual(parts?.fileIndex, 2)
        XCTAssertNil(coordinator.childParts(for: "report#1:0"))
        coordinator.removeBatch(batchId: "bundle")
        store.clear()
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

final class DownloadSessionIdentifiersTests: XCTestCase {
    func testRecognizesPluginSessionIdentifiers() {
        XCTAssertTrue(DownloadSessionIdentifiers.isPluginSession(DownloadSessionIdentifiers.main))
        XCTAssertTrue(DownloadSessionIdentifiers.isPluginSession(DownloadSessionIdentifiers.wifiOnly))
        XCTAssertFalse(DownloadSessionIdentifiers.isPluginSession("com.example.other"))
    }
}

final class DownloadBackgroundSessionManagerTests: XCTestCase {
    func testWarmUpCreatesDistinctBackgroundSessions() {
        let manager = DownloadBackgroundSessionManager.shared
        manager.warmUp()
        XCTAssertNotNil(manager.mainSession)
        XCTAssertNotNil(manager.wifiOnlySession)
        XCTAssertNotEqual(
            manager.mainSession.configuration.identifier,
            manager.wifiOnlySession.configuration.identifier
        )
        XCTAssertEqual(manager.mainSession.configuration.identifier, DownloadSessionIdentifiers.main)
        XCTAssertEqual(manager.wifiOnlySession.configuration.identifier, DownloadSessionIdentifiers.wifiOnly)
    }

    func testWarmUpIsIdempotent() {
        let manager = DownloadBackgroundSessionManager.shared
        manager.warmUp()
        let main = manager.mainSession
        manager.warmUp()
        XCTAssertTrue(main === manager.mainSession)
    }

    func testBackgroundEventsCompletionHandlerRunsForKnownSession() {
        let manager = DownloadBackgroundSessionManager.shared
        manager.warmUp()
        let expectation = expectation(description: "completion handler")
        manager.storeBackgroundEventsCompletionHandler({ expectation.fulfill() }, for: DownloadSessionIdentifiers.main)
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: manager.mainSession)
        wait(for: [expectation], timeout: 2)
    }

    func testSessionSelectionRespectsCellularPreference() {
        let manager = DownloadBackgroundSessionManager.shared
        manager.warmUp()
        XCTAssertTrue(manager.session(allowsCellularAccess: true, preferForegroundCapable: false) === manager.mainSession)
        XCTAssertTrue(manager.session(allowsCellularAccess: false, preferForegroundCapable: false) === manager.wifiOnlySession)
        XCTAssertTrue(manager.session(allowsCellularAccess: true, preferForegroundCapable: true) === manager.foregroundCapableSession)
    }
}

final class CapacitorDownloaderLifecycleTests: XCTestCase {
    func testIgnoresUnknownBackgroundSessionIdentifier() {
        let manager = DownloadBackgroundSessionManager.shared
        manager.warmUp()
        let expectation = expectation(description: "unknown session completes immediately")
        CapacitorDownloaderLifecycle.handleEventsForBackgroundURLSession(
            identifier: "com.example.other",
            completionHandler: { expectation.fulfill() }
        )
        wait(for: [expectation], timeout: 1)
    }

    func testStoresCompletionHandlerForPluginSession() {
        let manager = DownloadBackgroundSessionManager.shared
        manager.warmUp()
        let routed = expectation(description: "plugin session handler")
        CapacitorDownloaderLifecycle.handleEventsForBackgroundURLSession(
            identifier: DownloadSessionIdentifiers.main,
            completionHandler: { routed.fulfill() }
        )
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: manager.mainSession)
        wait(for: [routed], timeout: 2)
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
