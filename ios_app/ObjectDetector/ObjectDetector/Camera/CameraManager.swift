//
//  CameraManager.swift
//  ObjectDetector
//
//  Created by 九州工業大学 石井研究室アプリサービス係
//

import Foundation
import Combine
import AVFoundation
import UIKit

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published var detections: [Detection] = []
    
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let detector = YOLODetector()
    
    // 🚀 PIPELINE 1: Outbound TCP Transmission Link to USV / ROS Computer (Text Telemetry)
    private let transmitter = USVTransmissionClient()
    
    // 🚀 PIPELINE 2: Outbound TCP Transmission Link to Operator iPad (Video + Embedded JSON Telemetry)
    private let videoTransmitter = USVVideoTransmitter() // 🛠️ UNIQUE NAME TO FIX EXCLUSION ERRORS
    
    // Automation States
    var detectionEnabled = true
    private var frameCounter = 0
    private var currentInput: AVCaptureDeviceInput?
    
    // Performance Tracking Properties
    private var lastFrameTime = CFAbsoluteTimeGetCurrent()
    
    // Tracker to capture the absolute first hardware stream frame event
    private var isFirstFrameCaptured = false

    func startSession() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("❌ [USV Payload Error]: No camera hardware found.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            }

            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
                
                if let connection = videoOutput.connection(with: .video) {
                    connection.isVideoMirrored = false
                    connection.videoRotationAngle = 0
                }

                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]

                videoOutput.setSampleBufferDelegate(
                    self,
                    queue: DispatchQueue(label: "camera.frames.queue", qos: .userInteractive)
                )
            }
            
            detectionEnabled = true
            session.startRunning()
            print("🚀 [USV Engine Active]: Autonomous capture stream started successfully.")
            lastFrameTime = CFAbsoluteTimeGetCurrent()
        } catch {
            print("❌ [USV Payload Error]: Camera allocation error:", error)
        }
    }

    /// Interface method called by the UI layer to bind to the active USV ROS Node IP address (Port 7003)
    func connectToROS(ip: String) {
        transmitter.startTransmitter(to: ip)
    }
    
    /// Interface method for the UI layer to bind the video / data connection to the target iPad IP (Port 8002)
    func connectVideoToROS(ip: String) {
        videoTransmitter.startTransmitter(to: ip)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard detectionEnabled else { return }
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)

        // ⏱️ MILESTONE 2: Camera Stream Active (Fires once to log hardware readiness)
        if !isFirstFrameCaptured {
            isFirstFrameCaptured = true
            USVLogger.log(milestone: "CAMERA_STREAM_ACTIVE", details: "AVFoundation delivering frames to pipeline.")
        }

        // Frame dropping logic: Process every second frame to maintain strict UI fluidity
        frameCounter += 1
        if frameCounter % 2 != 0 { return }
        
        guard let validPixelBuffer = pixelBuffer else { return }

        // --- Calculate Live Frame Metrics ---
        let currentTime = CFAbsoluteTimeGetCurrent()
        let deltaTime = currentTime - lastFrameTime
        lastFrameTime = currentTime
        let currentFps = deltaTime > 0 ? 1.0 / deltaTime : 0.0
        
        // ⏱️ MILESTONE 3: Inference Start
        let t_inferenceStart = USVLogger.currentTimestamp
        
        // --- RUN DETECTION MODEL INFERENCE ---
        let incomingDetections = detector?.run(pixelBuffer: validPixelBuffer) ?? []
        
        // ⏱️ MILESTONE 4: Inference Complete
        let t_inferenceComplete = USVLogger.currentTimestamp
        
        // --- DATA SERIALIZATION FOR ROS ROUTER ---
        var telemetryString = ""
        let frameWidth: Float = 640.0
        let frameHeight: Float = 640.0
        
        if let primaryTarget = incomingDetections.first {
            let flag = 1
            
            // Map coordinates into normal linear center space (-1.0 to 1.0 range)
            let normalizedX = (primaryTarget.centerX - 320.0) / 320.0
            let normalizedY = (320.0 - primaryTarget.centerY) / 320.0
            
            let boxWidth = primaryTarget.width
            let boxHeight = primaryTarget.height
            
            telemetryString = String(format: "%d %.3f %.3f %.1f %.1f %.1f %.1f",
                                     flag, normalizedX, normalizedY, boxWidth, boxHeight, frameWidth, frameHeight)
        } else {
            telemetryString = String(format: "0 0.000 0.000 0.0 0.0 %.1f %.1f", frameWidth, frameHeight)
        }
        
        // 🚀 PIPELINE 1 OUTBOUND: Push telemetry
        transmitter.sendTelemetry(telemetryString)
        
        // 🚀 PIPELINE 2 OUTBOUND: Push video + layout packet structures to iPad
        if videoTransmitter.isConnected {
            let ciImage = CIImage(cvPixelBuffer: validPixelBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                
                if let jpegPayloadBytes = uiImage.jpegData(compressionQuality: 0.5) {
                    videoTransmitter.sendLiveFrame(
                        localDetections: incomingDetections,
                        rawTelemetry: telemetryString,
                        jpegData: jpegPayloadBytes
                    )
                }
            }
        }

        DispatchQueue.main.async {
            self.detections = incomingDetections
        }
    }
    
    /// Call this inside CameraManager class to clear and recreate connections from scratch
    func rebuildNetworkPipelines(robotIP: String, ipadIP: String) {
        print("🔄 [HARD RESET]: Tearing down and rebuilding all network sockets...")
        
        transmitter.disconnect()
        videoTransmitter.disconnect()
        
        transmitter.startTransmitter(to: robotIP)
        videoTransmitter.startTransmitter(to: ipadIP)
    }
}

// =========================================================================
// MARK: - Dedicated Outbound Video & JSON Array Transmitter Engine
// =========================================================================
final class USVVideoTransmitter {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "camera.video.tx.queue", qos: .userInteractive)
    
    var isConnected: Bool {
        return connection?.state == .ready
    }
    
    func startTransmitter(to ipAddress: String, port: UInt16 = 8002) {
        let host = NWEndpoint.Host(ipAddress)
        let nwPort = NWEndpoint.Port(integerLiteral: port)
        
        connection = NWConnection(host: host, port: nwPort, using: .tcp)
        connection?.stateUpdateHandler = { state in
            switch state {
            case .ready: print("✅ [iPad Video Link Active]")
            case .failed(let err): print("❌ [iPad Link Error]: \(err)")
            default: break
            }
        }
        connection?.start(queue: queue)
    }
    
    func disconnect() {
        print("🛑 [VIDEO TRANSMITTER]: Terminating socket context.")
        connection?.cancel()
        connection = nil
    }
    
    func sendLiveFrame(localDetections: [Detection], rawTelemetry: String, jpegData: Data) {
        guard isConnected else { return }
        
        let rosDetections = localDetections.map { det in
            ROSTelemetryDetection(
                objectClass: det.className,
                confidence: Double(det.confidence),
                normX: Double((det.centerX - 320.0) / 320.0),
                normY: Double((320.0 - det.centerY) / 320.0)
            )
        }
        
        let packet = iPadFramePacket(fps: 0.0, detections: rosDetections, rawLogString: rawTelemetry)
        guard let jsonData = try? JSONEncoder().encode(packet) else { return }
        
        var frameBuffer = Data()
        var jsonLength = UInt32(jsonData.count).bigEndian
        withUnsafeBytes(of: &jsonLength) { frameBuffer.append(contentsOf: $0) }
        frameBuffer.append(jsonData)
        
        var imageLength = UInt32(jpegData.count).bigEndian
        withUnsafeBytes(of: &imageLength) { frameBuffer.append(contentsOf: $0) }
        frameBuffer.append(jpegData)
        
        connection?.send(content: frameBuffer, completion: .contentProcessed({ _ in }))
    }
}
