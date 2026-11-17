import Capacitor
import Foundation

final class MaestroBridgeViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        #if DEBUG
        DispatchQueue.main.async { [weak self] in
            self?.bridge?.eval(js: "window.__capgoMaestroIsE2E=true;")
        }
        #endif
    }
}