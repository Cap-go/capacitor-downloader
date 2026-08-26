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
