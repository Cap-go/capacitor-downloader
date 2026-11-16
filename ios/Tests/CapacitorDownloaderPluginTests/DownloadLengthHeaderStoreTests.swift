import XCTest
@testable import CapacitorDownloaderPlugin

final class DownloadLengthHeaderStoreTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "CapacitorDownloaderLengthHeaderTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  func testPersistedStateSurvivesNewStoreInstance() {
    let store = DownloadLengthHeaderStore(defaults: defaults)
    store.setHeaderName("X-Uncompressed-Length", for: "task-1")
    store.setExpectedTotal(2048, for: "task-1")

    let reloaded = DownloadLengthHeaderStore(defaults: defaults)
    XCTAssertEqual(reloaded.headerName(for: "task-1"), "X-Uncompressed-Length")
    XCTAssertEqual(reloaded.expectedTotal(for: "task-1"), 2048)
  }

  func testClearRemovesPersistedEntries() {
    let store = DownloadLengthHeaderStore(defaults: defaults)
    store.setHeaderName("X-Uncompressed-Length", for: "task-2")
    store.setExpectedTotal(512, for: "task-2")

    store.clear(for: "task-2")

    XCTAssertNil(store.headerName(for: "task-2"))
    XCTAssertNil(store.expectedTotal(for: "task-2"))
    XCTAssertNil(defaults.dictionary(forKey: DownloadLengthHeaderStore.headerNamesDefaultsKey)?["task-2"])
    let totals = defaults.dictionary(forKey: DownloadLengthHeaderStore.expectedTotalsDefaultsKey) as? [String: NSNumber]
    XCTAssertNil(totals?["task-2"])
  }
}