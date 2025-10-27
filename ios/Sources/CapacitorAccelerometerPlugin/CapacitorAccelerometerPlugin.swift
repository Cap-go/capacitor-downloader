import Capacitor
import CoreMotion
import Foundation

@objc(CapacitorAccelerometerPlugin)
public class CapacitorAccelerometerPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CapacitorAccelerometerPlugin"
    public let jsName = "CapacitorAccelerometer"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getMeasurement", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startMeasurementUpdates", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopMeasurementUpdates", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeAllListeners", returnType: CAPPluginReturnPromise)
    ]

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private var latestMeasurement: [String: Double] = ["x": 0, "y": 0, "z": 0]

    public override func load() {
        super.load()
        queue.qualityOfService = .userInteractive
        motionManager.accelerometerUpdateInterval = 0.02
    }

    @objc func getMeasurement(_ call: CAPPluginCall) {
        guard motionManager.isAccelerometerAvailable else {
            call.reject("Accelerometer not available")
            return
        }
        call.resolve(latestMeasurement)
    }

    @objc func isAvailable(_ call: CAPPluginCall) {
        call.resolve(["isAvailable": motionManager.isAccelerometerAvailable])
    }

    @objc func startMeasurementUpdates(_ call: CAPPluginCall) {
        guard motionManager.isAccelerometerAvailable else {
            call.reject("Accelerometer not available")
            return
        }

        if motionManager.isAccelerometerActive {
            call.resolve()
            return
        }

        motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, error in
            guard let self, let data else {
                if let error {
                    CAPLog.print("CapacitorAccelerometerPlugin", "Accelerometer error: \(error.localizedDescription)")
                }
                return
            }

            let measurement: [String: Double] = [
                "x": data.acceleration.x,
                "y": data.acceleration.y,
                "z": data.acceleration.z
            ]
            self.latestMeasurement = measurement

            DispatchQueue.main.async {
                self.notifyListeners("measurement", data: measurement)
            }
        }

        call.resolve()
    }

    @objc func stopMeasurementUpdates(_ call: CAPPluginCall) {
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
        call.resolve()
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        call.resolve(["accelerometer": currentPermissionState()])
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        call.resolve(["accelerometer": currentPermissionState()])
    }

    @objc override public func removeAllListeners(_ call: CAPPluginCall) {
        super.removeAllListeners(call)
    }

    private func currentPermissionState() -> String {
        guard motionManager.isAccelerometerAvailable else {
            return "denied"
        }

        if #available(iOS 11.0, *) {
            switch CMMotionActivityManager.authorizationStatus() {
            case .authorized:
                return "granted"
            case .denied, .restricted:
                return "denied"
            case .notDetermined:
                return "prompt"
            @unknown default:
                return "prompt"
            }
        }

        return "granted"
    }
}
