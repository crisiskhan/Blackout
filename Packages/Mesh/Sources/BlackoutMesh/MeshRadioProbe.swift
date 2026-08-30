import BlackoutCore
import CoreBluetooth
import Foundation
import Network
import Observation

/// Bluetooth / Wi-Fi / Local Network radios. GPS is out of scope.
@MainActor
@Observable
public final class MeshRadioProbe: NSObject {
    public private(set) var bluetoothOff = false
    public private(set) var wifiOff = false
    public private(set) var localNetworkDenied = false

    public var cannotRun: Bool {
        MeshRadioBannerPolicy.cannotRun(
            bluetoothOff: bluetoothOff,
            wifiOff: wifiOff,
            localNetworkDenied: localNetworkDenied
        )
    }

    private var central: CBCentralManager?
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "blackout.mesh.radios")

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionShowPowerAlertKey: false
        ])
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.apply(path)
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    private func apply(_ path: NWPath) {
        wifiOff = !path.usesInterfaceType(.wifi)
        if path.status == .unsatisfied {
            switch path.unsatisfiedReason {
            case .localNetworkDenied:
                localNetworkDenied = true
            case .wifiDenied:
                wifiOff = true
            default:
                break
            }
        } else {
            localNetworkDenied = false
        }
    }
}

extension MeshRadioProbe: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothOff = false
        case .unauthorized, .poweredOff, .unsupported:
            bluetoothOff = true
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
    }
}
