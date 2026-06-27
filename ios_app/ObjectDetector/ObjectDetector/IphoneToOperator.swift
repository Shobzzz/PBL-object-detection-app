import Foundation
import UIKit
import Network
import Combine

struct ROSTelemetryDetection: Codable {
    let objectClass: String
    let confidence: Double
    let normX: Double
    let normY: Double
}

struct iPadFramePacket: Codable {
    let fps: Double
    let detections: [ROSTelemetryDetection]
    let rawLogString: String
}

class USVVideoReceiver: ObservableObject {
    
    @Published var receivedImage: UIImage? = nil
    @Published var receivedTelemetryString: String = "No Live Telemetry Stream"
    @Published var targetFps: Double = 0.0
    
    @Published var bytesReceived: Int = 0
    @Published var framesReceived: Int = 0
    
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let receiverQueue = DispatchQueue(label: "OperatorVideoReceiverQueue", qos: .userInteractive)
    
    private var buffer = Data()
    private var expectedLength: Int? = nil
    private var parsingState: ParsingPhase = .readingJsonLength
    
    private enum ParsingPhase {
        case readingJsonLength
        case readingJsonData
        case readingImageLength
        case readingImageData
    }
    
    func startListening(port: UInt16 = 8002) {
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("❌ Listener setup failed: \(error)")
            return
        }
        
        DispatchQueue.main.async {
            self.bytesReceived = 0
            self.framesReceived = 0
            self.receivedImage = nil
            self.receivedTelemetryString = "best 3.mlpackageected / Waiting for Stream"
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            print("📥 Connected to USV Payload Stream on port \(port)")
            
            if let old = self.activeConnection {
                print("⚠️ Closing duplicate pipeline session context.")
                old.cancel()
            }
            self.activeConnection = connection
            
            self.buffer.removeAll()
            self.expectedLength = nil
            self.parsingState = .readingJsonLength
            
            connection.start(queue: self.receiverQueue)
            self.receiveLoop(connection)
        }
        
        listener?.start(queue: receiverQueue)
        print("📡 Network Receiver listening on port \(port)")
    }
    
    // 🛠️ NEW: Fully isolates and flushes out old network descriptors on request
    func restartConnection(on port: UInt16 = 8002) {
        print("🔄 Initiating full network receiver pipeline teardown...")
        
        activeConnection?.cancel()
        activeConnection = nil
        
        listener?.cancel()
        listener = nil
        
        buffer.removeAll()
        expectedLength = nil
        parsingState = .readingJsonLength
        
        DispatchQueue.main.async {
            self.bytesReceived = 0
            self.framesReceived = 0
            self.receivedImage = nil
            self.receivedTelemetryString = "System Rebooted: Waiting for hardware..."
        }
        
        print("🚀 Re-allocating sockets. Starting listener...")
        startListening(port: port)
    }
    
    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                DispatchQueue.main.async { self.bytesReceived += data.count }
                self.buffer.append(data)
                self.enforceBufferLimit()
                self.processComplexPayload()
            }
            
            if let error = error {
                print("❌ TCP Pipeline session dropped: \(error)")
                if connection === self.activeConnection { self.activeConnection = nil }
                return
            }
            
            if isComplete {
                print("ℹ️ Stream ended gracefully by remote asset.")
                if connection === self.activeConnection { self.activeConnection = nil }
                return
            }
            
            self.receiveLoop(connection)
        }
    }
    
    private func enforceBufferLimit(maxSize: Int = 1_000_000) {
        if buffer.count > maxSize {
            print("⚠️ Memory threshold reached — dropping unparsed frame packets")
            buffer.removeAll()
            expectedLength = nil
            parsingState = .readingJsonLength
        }
    }
    
    private func processComplexPayload() {
        while true {
            switch parsingState {
            case .readingJsonLength:
                guard buffer.count >= 4 else { return }
                let lengthBytes = buffer.prefix(4)
                buffer.removeFirst(4)
                
                var value: UInt32 = 0
                for b in lengthBytes { value = (value << 8) | UInt32(b) }
                expectedLength = Int(value)
                parsingState = .readingJsonData
                
            case .readingJsonData:
                guard let targetLen = expectedLength else { return }
                guard buffer.count >= targetLen else { return }
                
                let jsonData = Data(buffer.prefix(targetLen))
                buffer.removeFirst(targetLen)
                
                if let packet = try? JSONDecoder().decode(iPadFramePacket.self, from: jsonData) {
                    DispatchQueue.main.async {
                        self.receivedTelemetryString = packet.rawLogString
                        self.targetFps = packet.fps
                    }
                }
                
                expectedLength = nil
                parsingState = .readingImageLength
                
            case .readingImageLength:
                guard buffer.count >= 4 else { return }
                let lengthBytes = buffer.prefix(4)
                buffer.removeFirst(4)
                
                var value: UInt32 = 0
                for b in lengthBytes { value = (value << 8) | UInt32(b) }
                expectedLength = Int(value)
                parsingState = .readingImageData
                
            case .readingImageData:
                guard let targetLen = expectedLength else { return }
                guard buffer.count >= targetLen else { return }
                
                let imgData = Data(buffer.prefix(targetLen))
                buffer.removeFirst(targetLen)
                
                if let image = UIImage(data: imgData) {
                    DispatchQueue.main.async {
                        self.receivedImage = image
                        self.framesReceived += 1
                    }
                } else {
                    print("❌ Image decoding pipeline mismatch.")
                }
                
                expectedLength = nil
                parsingState = .readingJsonLength
            }
        }
    }
}
