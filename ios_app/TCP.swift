import Foundation
import Network

struct FramePacket: Codable {
    let fps: Double
    let detections: [Detection]
}

struct Detection: Codable {
    let objectClass: String
    let confidence: Double
    let normX: Double
    let normY: Double
}

final class TCPTransmitter: ObservableObject {
    
    // MARK: - Network
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "usv.transmission.queue", qos: .userInteractive)
    
    @Published var isConnected = false
    
    private var currentTargetIP: String = "192.168.0.10"
    private let hostPort: UInt16 = 7003
    
    // MARK: - Sending control
    private var sendTimer: DispatchSourceTimer?
    private var interval: TimeInterval = 1.0 / 15.0 // 15 FPS target
    private var frameIndex = 0
    
    // Example data (replace with YOLO results later)
    private let FPS: Double = 15.0
    private let frames: [[Detection]] = [
        [
            Detection(objectClass: "white_buoy", confidence: 0.85, normX: 0.1, normY: 0.1),
            Detection(objectClass: "orange_buoy", confidence: 0.9, normX: 0.2, normY: -0.1)
        ]
    ]
    
    // Replace with real image later
    private let imageData: Data = {
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "jpg"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Image not found in bundle")
        }
        return data
    }()
    
    // MARK: - Public start
    func startTransmitter(to ip: String) {
        
        guard ip != currentTargetIP else { return }
        
        disconnect()
        
        currentTargetIP = ip
        
        print("⏳ Connecting to \(ip):\(hostPort)")
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: hostPort)!
        )
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        
        connection = NWConnection(to: endpoint, using: params)
        
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
                
            case .ready:
                DispatchQueue.main.async {
                    self.isConnected = true
                }
                print("🔗 [NETWORK LINK CONNECTED]: Successfully handshaked with ROS node at \(ip)")
                
                self.startSendingLoop()
                
            case .failed(let error):
                DispatchQueue.main.async {
                    self.isConnected = false
                }
                print("❌ [NETWORK LINK ERROR]: Connection dropped (\(error.localizedDescription)). Retrying in 3 seconds...")
                self.retryConnection()
                
            case .cancelled:
                DispatchQueue.main.async {
                    self.isConnected = false
                }
                print("🛑 [NETWORK LINK]: Transmission stream closed.")
                
            default:
                break
            }
        }
        
        connection?.start(queue: queue)
    }
    
    // MARK: - Sending loop
    
    private func startSendingLoop() {
        
        sendTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: queue)
        
        timer.schedule(
            deadline: .now(),
            repeating: interval
        )
        
        timer.setEventHandler { [weak self] in
            self?.sendFrame()
        }
        
        sendTimer = timer
        timer.resume()
    }
    
    private func sendFrame() {
        guard let connection = connection, isConnected else { return }
        
        let startTime = Date()
        
        let dets = frames[frameIndex % frames.count]
        
        let packet = FramePacket(fps: FPS, detections: dets)
        
        guard let jsonData = try? JSONEncoder().encode(packet) else { return }
        
        let jsonLen = UInt32(jsonData.count)
        let imgLen = UInt32(imageData.count)
        
        var buffer = Data()
        
        // JSON length
        var jsonBE = jsonLen.bigEndian
        withUnsafeBytes(of: &jsonBE) {
            buffer.append(contentsOf: $0)
        }
        
        // JSON
        buffer.append(jsonData)
        
        // Image length
        var imgBE = imgLen.bigEndian
        withUnsafeBytes(of: &imgBE) {
            buffer.append(contentsOf: $0)
        }
        
        // Image
        buffer.append(imageData)
        
        connection.send(content: buffer, completion: .contentProcessed { error in
            if let error = error {
                print("⚠️ [NETWORK TRANSMIT ERROR]: Failed to deliver packet stream bytes: \(error)")
            }
        })
        
        frameIndex += 1
        
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed > 0.1 {
            print("⚠️ [NETWORK TRANSMIT WARNING]: Slow frame detected (\(elapsed)s)")
        }
    }
    
    // MARK: - Retry
    
    private func retryConnection() {
        guard !currentTargetIP.isEmpty else { return }
        
        queue.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            self.startTransmitter(to: self.currentTargetIP)
        }
    }
    
    // MARK: - Disconnect
    
    func disconnect() {
        sendTimer?.cancel()
        sendTimer = nil
        
        connection?.cancel()
        connection = nil
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}