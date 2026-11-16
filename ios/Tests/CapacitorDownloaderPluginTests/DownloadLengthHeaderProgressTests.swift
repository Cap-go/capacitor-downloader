import XCTest
@testable import CapacitorDownloaderPlugin

final class DownloadLengthHeaderProgressTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "CapacitorDownloaderLengthHeaderProgress.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  func testPrefersLengthHeaderTotalOverNativeExpectedTotal() {
    let store = DownloadLengthHeaderStore(defaults: defaults)
    store.setHeaderName("X-Uncompressed-Length", for: "dl-1")
    store.setExpectedTotal(1000, for: "dl-1")

    let snapshot = DownloadLengthHeaderProgress.bytesTotalAndProgress(
      downloadId: "dl-1",
      totalBytesWritten: 100,
      totalBytesExpectedToWrite: 100
    )
    XCTAssertEqual(snapshot.bytesTotal, 1000)
    XCTAssertEqual(snapshot.progress, 0.1, accuracy: 0.0001)
  }

  func testProgressClampedWhenBytesWrittenExceedHeaderTotal() {
    let store = DownloadLengthHeaderStore(defaults: defaults)
    store.setExpectedTotal(100, for: "dl-2")

    let snapshot = DownloadLengthHeaderProgress.bytesTotalAndProgress(
      downloadId: "dl-2",
      totalBytesWritten: 250,
      totalBytesExpectedToWrite: 0
    )
    XCTAssertEqual(snapshot.bytesTotal, 100)
    XCTAssertEqual(snapshot.progress, 1)
  }
}