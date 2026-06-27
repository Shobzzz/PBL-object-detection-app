import Foundation
import Network
import Combine

final class USVTransmissionClient: ObservableObject {
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "usv.transmission.queue", qos: .userInteractive)
    
    @Published var isConnected = false
    private var currentTargetIP: String = ""
    private let hostPort: UInt16 = 7003  // Dedicated port for your teammate's ROS socket listener

    /// Call this function when you ready to feed the actual IP assigned by the Android Hotspot
    func startTransmitter(to ip: String) {
        // Prevent re-initialization if already attempting connection to the same host
        guard ip != currentTargetIP || !isConnected else { return }
        
        disconnect()
        self.currentTargetIP = ip
        print("⏳ [NETWORK LINK]: Initializing socket pipeline to target host: \(ip):\(hostPort)")
        
        let serverEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: hostPort)!)
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true // Disable packet buffering to guarantee minimum telemetry latency
        
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        connection = NWConnection(to: serverEndpoint, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async { self?.isConnected = true }
                USVLogger.log(milestone: "TELEMETRY_LINK_READY", details: "Handshake completed with ROS node at \(ip)")
                
            case .failed(let error):
                DispatchQueue.main.async { self?.isConnected = false }
                USVLogger.log(milestone: "TELEMETRY_LINK_FAILED", details: error.localizedDescription)
                self?.retryConnection()
            default:
                break
            }
        }
        
        connection?.start(queue: queue)
    }
    
    private func retryConnection() {
        guard !currentTargetIP.isEmpty else { return }
        queue.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            self.startTransmitter(to: self.currentTargetIP)
        }
    }
    
    /// Pushes the formatted space-separated telemetry packet string to the ROS environment
    func sendTelemetry(_ payload: String) {
        if !isConnected {
            print("🔬 [SIMULATED TX PACKET]: Would send -> \"\(payload)\\n\"")
        }

        guard isConnected, let connection = connection else { return }
        
        let completePacket = payload + "\n"
        guard let data = completePacket.data(using: .utf8) else { return }
        
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("⚠️ [NETWORK TRANSMIT ERROR]: Failed to deliver packet stream bytes: \(error)")
            }
        }))
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async { self.isConnected = false }
    }
}
