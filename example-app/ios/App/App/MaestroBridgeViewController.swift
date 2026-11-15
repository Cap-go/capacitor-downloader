import Capacitor
import Foundation

final class MaestroBridgeViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        #if DEBUG
        bridge?.eval(js: "window.__capgoMaestroIsE2E=true;")
        #endif
    }
}