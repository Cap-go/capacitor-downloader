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

    func testFilesPrefixUsesDocumentsSubfolder() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "files/offline/map.zip",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )
        XCTAssertEqual(url, documentsDirectory.appendingPathComponent("files/offline/map.zip"))
    }

    func testCachePrefixUsesDocumentsCacheSubfolder() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "cache/temp.bin",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )
        XCTAssertEqual(url, documentsDirectory.appendingPathComponent("cache/temp.bin"))
    }

    func testFilesPrefixWithEmptyRelativeReturnsNil() {
        let documents = URL(fileURLWithPath: "/var/mobile/Documents")
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "files/",
            id: "",
            documentsDirectory: documents
        )
        XCTAssertNil(url)
    }

    func testTraversalInFilesPrefixIsRejected() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "files/../secret.txt",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )
        XCTAssertNil(url)
    }

    func testTraversalInCachePrefixIsRejected() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "cache/../../tmp/evil.bin",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )
        XCTAssertNil(url)
    }

    func testTraversalInPrivatePrefixIsRejected() {
        let url = DownloadDestinationResolver.resolveDestinationURL(
            destination: "private/../../tmp/evil.bin",
            id: "download-1",
            documentsDirectory: documentsDirectory
        )
        XCTAssertNil(url)
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
        guard let resolved = DownloadDestinationResolver.resolveDestinationURL(
            destination: whitespace,
            id: childId,
            documentsDirectory: documents
        ) else {
            XCTFail("expected resolved destination")
            return
        }
        let resolvedPath = resolved.path

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
        )?.path
        XCTAssertNotEqual(mistakenCleanupTarget, resolvedPath)

        coordinator.removeBatch(batchId: "bundle")
        store.clear()
    }

    func testLoadRestoresGenerationsBeforeRegisteringDelegate() {
        DownloadIdGenerationStore.shared.setGeneration(11, forDownloadId: "episode")
        let plugin = CapacitorDownloaderPlugin()
        plugin.load()
        XCTAssertTrue(plugin.didRestoreGenerationsBeforeDelegateRegistration)
    }

    func testLoadRestoresBackgroundTasksForMainAndWifiOnlySessions() {
        let plugin = CapacitorDownloaderPlugin()
        XCTAssertFalse(plugin.hasRegisteredTask(id: "restored-single"))

        plugin.load()
        XCTAssertTrue(plugin.restoredBackgroundSessionIdentifiers.contains(DownloadSessionIdentifiers.main))
        XCTAssertTrue(plugin.restoredBackgroundSessionIdentifiers.contains(DownloadSessionIdentifiers.wifiOnly))

        // Simulators cannot create background URLSession download tasks reliably; exercise rehydration directly.
        let session = DownloadBackgroundSessionManager.shared.session(
            allowsCellularAccess: true,
            preferForegroundCapable: true
        )
        let downloadTask = session.downloadTask(with: URL(string: "https://example.com/file.bin")!)
        downloadTask.taskDescription = "restored-single"
        plugin.rehydrateBackgroundDownloadTasks([downloadTask])
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

    func testBatchCoordinatorAcceptsLargeFileCount() {
        let store = DownloadBatchStore(defaults: batchDefaults)
        let coordinator = DownloadBatchCoordinator(store: store)
        guard let generation = coordinator.startBatch(batchId: "big", fileCount: 40, singleDownloadIds: []) else {
            XCTFail("expected batch to start")
            return
        }
        XCTAssertGreaterThan(generation, 0)
        coordinator.removeBatch(batchId: "big")
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
        store.setGeneration(7, forSessionIdentifier: DownloadSessionIdentifiers.main, taskIdentifier: 42)
        let key = DownloadTaskGenerationKey.storageKey(sessionIdentifier: DownloadSessionIdentifiers.main, taskIdentifier: 42)
        XCTAssertEqual(store.allGenerations()[key], 7)
        store.removeGeneration(forSessionIdentifier: DownloadSessionIdentifiers.main, taskIdentifier: 42)
        XCTAssertNil(store.allGenerations()[key])
    }

    func testSameTaskIdentifierAcrossSessionsDoesNotCollide() {
        store.setGeneration(1, forSessionIdentifier: DownloadSessionIdentifiers.main, taskIdentifier: 9)
        store.setGeneration(2, forSessionIdentifier: DownloadSessionIdentifiers.wifiOnly, taskIdentifier: 9)
        store.setGeneration(3, forSessionIdentifier: DownloadSessionIdentifiers.foregroundCapable, taskIdentifier: 9)
        let all = store.allGenerations()
        XCTAssertEqual(
            all[DownloadTaskGenerationKey.storageKey(sessionIdentifier: DownloadSessionIdentifiers.main, taskIdentifier: 9)],
            1
        )
        XCTAssertEqual(
            all[DownloadTaskGenerationKey.storageKey(sessionIdentifier: DownloadSessionIdentifiers.wifiOnly, taskIdentifier: 9)],
            2
        )
        XCTAssertEqual(
            all[DownloadTaskGenerationKey.storageKey(sessionIdentifier: DownloadSessionIdentifiers.foregroundCapable, taskIdentifier: 9)],
            3
        )
    }

    func testLegacyBareTaskIdentifierMapsToMainSession() {
        defaults.set(["55": NSNumber(value: 4)], forKey: DownloadTaskGenerationStore.userDefaultsKey)
        let key = DownloadTaskGenerationKey.storageKey(sessionIdentifier: DownloadSessionIdentifiers.main, taskIdentifier: 55)
        XCTAssertEqual(store.allGenerations()[key], 4)
    }
}

final class DownloadSessionIdentifiersTests: XCTestCase {
    func testRecognizesPluginSessionIdentifiers() {
        XCTAssertTrue(DownloadSessionIdentifiers.isPluginSession(DownloadSessionIdentifiers.main))
        XCTAssertTrue(DownloadSessionIdentifiers.isPluginSession(DownloadSessionIdentifiers.wifiOnly))
        XCTAssertFalse(DownloadSessionIdentifiers.isPluginSession("com.example.other"))
    }

    func testContinuedProcessingIdentifiersUseBundlePrefix() {
        let bundleId = Bundle.main.bundleIdentifier ?? "CapacitorDownloader"
        let taskId = DownloadSessionIdentifiers.continuedProcessingTaskIdentifier()
        XCTAssertTrue(taskId.hasPrefix(bundleId + DownloadSessionIdentifiers.continuedProcessingSuffix))
        XCTAssertEqual(
            DownloadSessionIdentifiers.continuedProcessingPermittedIdentifierPattern(),
            bundleId + DownloadSessionIdentifiers.continuedProcessingSuffix + "*"
        )
    }
}

private final class SynchronousFinishDelegate: NSObject, URLSessionDownloadDelegate {
    var finishCallCount = 0
    var locationExistedAtFinish = false

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        finishCallCount += 1
        locationExistedAtFinish = FileManager.default.fileExists(atPath: location.path)
    }
}

final class DownloadBackgroundSessionManagerTests: XCTestCase {
    override func tearDown() {
        DownloadBackgroundSessionManager.forceProductionRegistrationQueueForTests = false
        DownloadBackgroundSessionManager.deferredHandlerFallbackIntervalForTests = 20
        DownloadBackgroundSessionManager.shared.resetSessionManagerStateForTests()
        super.tearDown()
    }

    func testRegisteredDelegateReceivesFinishSynchronouslyBeforeCallbackReturns() {
        let manager = DownloadBackgroundSessionManager.shared
        manager.warmUp()
        let delegate = SynchronousFinishDelegate()
        manager.register(downloadDelegate: delegate)

        let location = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapacitorDownloaderFinishSync-\(UUID().uuidString)")
        try? Data("payload".utf8).write(to: location)
        defer { try? FileManager.default.removeItem(at: location) }

        guard let session = manager.foregroundCapableSession else {
            XCTFail("foregroundCapableSession missing")
            return
        }
        let task = session.downloadTask(with: URL(string: "https://example.invalid/finish-sync")!)
        manager.urlSession(session, downloadTask: task, didFinishDownloadingTo: location)

        XCTAssertEqual(delegate.finishCallCount, 1)
        XCTAssertTrue(delegate.locationExistedAtFinish)
    }

    func testRegisterUsesDelegateQueueInProductionPath() {
        DownloadBackgroundSessionManager.forceProductionRegistrationQueueForTests = true
        let manager = DownloadBackgroundSessionManager.shared
        manager.resetSessionManagerStateForTests()
        manager.warmUp()

        let queueEntered = expectation(description: "delegate queue blocked")
        let releaseQueue = DispatchSemaphore(value: 0)
        manager.delegateQueueForTests.addOperation {
            queueEntered.fulfill()
            releaseQueue.wait()
        }
        wait(for: [queueEntered], timeout: 1)

        let delegate = SynchronousFinishDelegate()
        manager.register(downloadDelegate: delegate)
        XCTAssertFalse(
            manager.hasRegisteredDownloadDelegateForTests,
            "register must enqueue on delegateQueue, not run on the caller"
        )

        releaseQueue.signal()
        let registrationFinished = expectation(description: "registration finished")
        manager.delegateQueueForTests.addOperation {
            registrationFinished.fulfill()
        }
        wait(for: [registrationFinished], timeout: 1)
        XCTAssertTrue(manager.hasRegisteredDownloadDelegateForTests)
    }

    func testStagedFinishSurvivesEarlyFlushUntilRegister() {
        let manager = DownloadBackgroundSessionManager.shared
        manager.resetSessionManagerStateForTests()
        manager.warmUp()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapacitorDownloaderStaged-\(UUID().uuidString)")
        try? Data("staged-payload".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let session = manager.mainSession else {
            XCTFail("mainSession missing")
            return
        }
        let task = session.downloadTask(with: URL(string: "https://example.invalid/staged-finish")!)
        manager.urlSession(session, downloadTask: task, didFinishDownloadingTo: tempURL)
        XCTAssertGreaterThan(manager.pendingFinishCountForTests, 0)

        var appDelegateCallCount = 0
        let appDelegateCompletion = expectation(description: "AppDelegate completion deferred")
        manager.storeBackgroundEventsCompletionHandler({
            appDelegateCallCount += 1
            appDelegateCompletion.fulfill()
        }, for: DownloadSessionIdentifiers.main)
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: session)

        let earlyFlushCompleted = expectation(description: "early flush on delegate queue")
        manager.delegateQueueForTests.addOperation {
            earlyFlushCompleted.fulfill()
        }
        wait(for: [earlyFlushCompleted], timeout: 1)

        let mainQueueDrained = expectation(description: "main queue drained")
        DispatchQueue.main.async { mainQueueDrained.fulfill() }
        wait(for: [mainQueueDrained], timeout: 1)

        let delegate = SynchronousFinishDelegate()
        XCTAssertEqual(delegate.finishCallCount, 0)
        XCTAssertEqual(appDelegateCallCount, 0, "AppDelegate handler must not run before register")
        XCTAssertGreaterThan(manager.pendingFinishCountForTests, 0, "early flush must not drop staged finishes")

        manager.register(downloadDelegate: delegate)

        XCTAssertEqual(delegate.finishCallCount, 1)
        XCTAssertTrue(delegate.locationExistedAtFinish)
        XCTAssertEqual(manager.pendingFinishCountForTests, 0)
        wait(for: [appDelegateCompletion], timeout: 1)
        XCTAssertEqual(appDelegateCallCount, 1, "AppDelegate handler must run exactly once after register")
    }

    func testStoredHandlerRunsOnceAcrossRepeatedFinishEvents() {
        let manager = DownloadBackgroundSessionManager.shared
        manager.resetSessionManagerStateForTests()
        manager.warmUp()
        var handlerCallCount = 0
        let handlerCalled = expectation(description: "handler called once")
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: manager.mainSession)
        manager.storeBackgroundEventsCompletionHandler({
            handlerCallCount += 1
            handlerCalled.fulfill()
        }, for: DownloadSessionIdentifiers.main)
        let firstRound = expectation(description: "first handler flush")
        manager.delegateQueueForTests.addOperation { firstRound.fulfill() }
        wait(for: [handlerCalled, firstRound], timeout: 1)
        XCTAssertEqual(handlerCallCount, 1)
        let secondRound = expectation(description: "second finish events")
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: manager.mainSession)
        manager.delegateQueueForTests.addOperation { secondRound.fulfill() }
        wait(for: [secondRound], timeout: 1)
        XCTAssertEqual(handlerCallCount, 1)
    }

    func testDeferredHandlerFallbackRunsOnceWhenPluginNeverRegisters() {
        DownloadBackgroundSessionManager.deferredHandlerFallbackIntervalForTests = 0.05
        let manager = DownloadBackgroundSessionManager.shared
        manager.resetSessionManagerStateForTests()
        manager.warmUp()

        guard let session = manager.mainSession else {
            XCTFail("mainSession missing")
            return
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("CapacitorDownloaderFallback-\(UUID().uuidString)")
        try? Data("fallback".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let task = session.downloadTask(with: URL(string: "https://example.invalid/fallback")!)
        manager.urlSession(session, downloadTask: task, didFinishDownloadingTo: tempURL)

        var fallbackCallCount = 0
        let fallbackRan = expectation(description: "fallback handler")
        manager.storeBackgroundEventsCompletionHandler({
            fallbackCallCount += 1
            fallbackRan.fulfill()
        }, for: DownloadSessionIdentifiers.main)
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: session)
        let earlyFlushCompleted = expectation(description: "early flush")
        manager.delegateQueueForTests.addOperation { earlyFlushCompleted.fulfill() }
        wait(for: [earlyFlushCompleted], timeout: 1)
        XCTAssertGreaterThan(manager.pendingFinishCountForTests, 0)

        wait(for: [fallbackRan], timeout: 1)
        XCTAssertEqual(fallbackCallCount, 1)
        XCTAssertGreaterThan(manager.pendingFinishCountForTests, 0, "staged events must survive fallback")
    }

    func testRegisterBeforeFallbackPreventsDoubleAppDelegateHandler() {
        DownloadBackgroundSessionManager.deferredHandlerFallbackIntervalForTests = 0.2
        let manager = DownloadBackgroundSessionManager.shared
        manager.resetSessionManagerStateForTests()
        manager.warmUp()

        guard let session = manager.mainSession else {
            XCTFail("mainSession missing")
            return
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("CapacitorDownloaderRegisterFirst-\(UUID().uuidString)")
        try? Data("reg-first".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let task = session.downloadTask(with: URL(string: "https://example.invalid/register-first")!)
        manager.urlSession(session, downloadTask: task, didFinishDownloadingTo: tempURL)

        var handlerCallCount = 0
        let handlerCalled = expectation(description: "handler after register")
        manager.storeBackgroundEventsCompletionHandler({
            handlerCallCount += 1
            handlerCalled.fulfill()
        }, for: DownloadSessionIdentifiers.main)
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: session)
        let earlyFlushCompleted = expectation(description: "early flush")
        manager.delegateQueueForTests.addOperation { earlyFlushCompleted.fulfill() }
        wait(for: [earlyFlushCompleted], timeout: 1)

        manager.register(downloadDelegate: SynchronousFinishDelegate())
        wait(for: [handlerCalled], timeout: 1)
        XCTAssertEqual(handlerCallCount, 1)

        let fallbackGrace = expectation(description: "fallback window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            fallbackGrace.fulfill()
        }
        wait(for: [fallbackGrace], timeout: 1)
        XCTAssertEqual(handlerCallCount, 1)
    }

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

    func testBackgroundEventsCompletionHandlerRunsWhenStoredAfterFinishEvents() {
        let manager = DownloadBackgroundSessionManager.shared
        manager.warmUp()
        let expectation = expectation(description: "late stored handler")
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: manager.mainSession)
        manager.storeBackgroundEventsCompletionHandler({ expectation.fulfill() }, for: DownloadSessionIdentifiers.main)
        wait(for: [expectation], timeout: 2)
    }

    func testCompletionTextRequiresMatchingGenerationAfterRestore() {
        let idDefaults = UserDefaults(suiteName: "CapacitorDownloaderRelaunchGenerationTests")!
        idDefaults.removePersistentDomain(forName: "CapacitorDownloaderRelaunchGenerationTests")
        let textDefaults = UserDefaults(suiteName: "CapacitorDownloaderRelaunchTextTests")!
        textDefaults.removePersistentDomain(forName: "CapacitorDownloaderRelaunchTextTests")

        let idStore = DownloadIdGenerationStore(defaults: idDefaults)
        idStore.setGeneration(4, forDownloadId: "episode")
        let textStore = DownloadCompletedNotificationStore(defaults: textDefaults)
        textStore.setText("Done", for: "episode", generation: 4)

        let restoredGenerations = DownloadIdGenerationStore(defaults: idDefaults).allGenerations()
        XCTAssertEqual(restoredGenerations["episode"], 4)
        XCTAssertNil(textStore.takeText(for: "episode", generation: 3))
        XCTAssertEqual(textStore.takeText(for: "episode", generation: 4), "Done")

        idDefaults.removePersistentDomain(forName: "CapacitorDownloaderRelaunchGenerationTests")
        textDefaults.removePersistentDomain(forName: "CapacitorDownloaderRelaunchTextTests")
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
