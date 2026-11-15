import Capacitor
import Foundation

final class MaestroBridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        #if DEBUG
        bridge?.eval(js: "window.__capgoMaestroIsE2E=true;", completion: nil)
        #endif
        super.capacitorDidLoad()
    }
}