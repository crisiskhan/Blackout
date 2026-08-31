import BlackoutCore
import CoreBluetooth
import Foundation
import Network
import Observation

/// Bluetooth / Wi-Fi / Local Network radios. GPS is out of scope.
/// Must not construct CBCentralManager or start NWPathMonitor until unlock.
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
    private var started = false

    public override init() {
        super.init()
    }

    public func start() {
        guard !started else { return }
        started = true
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
        var wifiDenied = false
        if path.status == .unsatisfied {
            switch path.unsatisfiedReason {
            case .localNetworkDenied:
                localNetworkDenied = true
            case .wifiDenied:
                wifiDenied = true
            case .notAvailable, .cellularDenied:
                break
            @unknown default:
                break
            }
        } else {
            localNetworkDenied = false
        }
        wifiOff = MeshRadioPathHonesty.wifiRadioOff(wifiDenied: wifiDenied)
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
