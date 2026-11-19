import Capacitor
import Foundation

final class MaestroBridgeViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        #if DEBUG
        DispatchQueue.main.async { [weak self] in
            var js = "window.__capgoMaestroIsE2E=true;"
            if let port = ProcessInfo.processInfo.environment["CAPGO_MAESTRO_PORT"], !port.isEmpty {
                js += "window.__capgoMaestroServerPort='\(port)';"
            }
            self?.bridge?.eval(js: js)
        }
        #endif
    }
}