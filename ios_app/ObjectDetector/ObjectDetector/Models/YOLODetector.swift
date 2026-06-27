//import CoreML
//import UIKit
//import CoreImage
//
//final class YOLODetector {
//
//    private let model: best
//    // High-performance GPU context for instant resizing
//    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
//    
//    // 🎛️ ADJUST SENSITIVITY HERE: 0.55 means the model must be 55% certain it's a buoy
//    private let confidenceThreshold: Float = 0.60
//    private let nmsThreshold: Float = 0.80
//
//    init?() {
//        do {
//            let config = MLModelConfiguration()
//            config.computeUnits = .all
//            model = try best(configuration: config)
//        } catch {
//            print("Failed to load model:", error)
//            return nil
//        }
//    }
//
//    /// Resizes a CVPixelBuffer to 640x640 using high-performance Core Image scaling
//    private func resizePixelBuffer(_ srcBuffer: CVPixelBuffer, targetWidth: Int = 640, targetHeight: Int = 640) -> CVPixelBuffer? {
//        let srcImage = CIImage(cvPixelBuffer: srcBuffer)
//        
//        // Calculate scale factors to match 640x640
//        let scaleX = CGFloat(targetWidth) / CGFloat(CVPixelBufferGetWidth(srcBuffer))
//        let scaleY = CGFloat(targetHeight) / CGFloat(CVPixelBufferGetHeight(srcBuffer))
//        
//        // Scale the image
//        let scaledImage = srcImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
//        
//        // Create an empty destination pixel buffer
//        var dstBuffer: CVPixelBuffer?
//        let attrs = [
//            kCVPixelBufferCGImageCompatibilityKey: true,
//            kCVPixelBufferCGBitmapContextCompatibilityKey: true
//        ] as CFDictionary
//        
//        let status = CVPixelBufferCreate(
//            kCFAllocatorDefault,
//            targetWidth,
//            targetHeight,
//            kCVPixelFormatType_32BGRA, // Match your camera format
//            attrs,
//            &dstBuffer
//        )
//        
//        guard status == kCVReturnSuccess, let outputBuffer = dstBuffer else {
//            return nil
//        }
//        
//        // Render directly into the new destination buffer using the GPU context
//        ciContext.render(scaledImage, to: outputBuffer)
//        return outputBuffer
//    }
//
//    func run(pixelBuffer: CVPixelBuffer) -> [Detection] {
//        // 1. High-speed GPU Resize
//        let resizeStart = CFAbsoluteTimeGetCurrent()
//        guard let resizedBuffer = resizePixelBuffer(pixelBuffer) else {
//            print("GPU Resize Failed")
//            return []
//        }
//        let resizeTime = (CFAbsoluteTimeGetCurrent() - resizeStart) * 1000
//        print(String(format: "GPU Buffer Resize Time: %.2f ms", resizeTime))
//
//        // 2. Inference Loop
//        do {
//            let inferenceStart = CFAbsoluteTimeGetCurrent()
//            let input = bestInput(image: resizedBuffer)
//            let output = try model.prediction(input: input)
//
//            let inferenceTime = (CFAbsoluteTimeGetCurrent() - inferenceStart) * 1000
//            print(String(format: "Inference Time: %.2f ms", inferenceTime))
//
//            let array = output.var_1135
//            
//            // Fast Pointer Access
//            guard let pointer = try? UnsafeBufferPointer<Float32>(array) else {
//                return []
//            }
//            
//            let numCandidates = 8400
//            
//            // Channel offsets matching your model layout matrix dimensions
//            let ch0Offset = 0 * numCandidates // centerX
//            let ch1Offset = 1 * numCandidates // centerY
//            let ch2Offset = 2 * numCandidates // width
//            let ch3Offset = 3 * numCandidates // height
//            let ch4Offset = 4 * numCandidates // confidence_score
//
//            var detections: [Detection] = []
//            let postProcessStart = CFAbsoluteTimeGetCurrent()
//
//            for candidate in 0..<numCandidates {
//                let confidence = pointer[ch4Offset + candidate]
//
//                // ❌ FILTER: Drop anything below the new confidence threshold
//                if confidence < confidenceThreshold { continue }
//
//                let centerX = pointer[ch0Offset + candidate]
//                let centerY = pointer[ch1Offset + candidate]
//                let width = pointer[ch2Offset + candidate]
//                let height = pointer[ch3Offset + candidate]
//
//                // Fixes Error 1: Extracted directly as native Float type to match your Detection Struct
//                let detection = Detection(
//                    className: "white_buoy",
//                    confidence: confidence,
//                    centerX: centerX,
//                    centerY: centerY,
//                    width: width,
//                    height: height
//                )
//                detections.append(detection)
//            }
//
//            // 🚀 Collapse duplicate overlaps into single target objects
//            let filtered = nonMaximumSuppression(detections: detections, iouThreshold: nmsThreshold)
//            let postProcessTime = (CFAbsoluteTimeGetCurrent() - postProcessStart) * 1000
//            
//            print(String(format: "Filtered Output Targets Count: %d | Post Process: %.2f ms", filtered.count, postProcessTime))
//            return filtered
//
//        } catch {
//            print("Prediction error:", error)
//            return []
//        }
//    }
//    
//    private func nonMaximumSuppression(detections: [Detection], iouThreshold: Float) -> [Detection] {
//        let sortedDetections = detections.sorted { $0.confidence > $1.confidence }
//        var keptDetections: [Detection] = []
//        var ignoredIndices = Set<Int>()
//        
//        for i in 0..<sortedDetections.count {
//            if ignoredIndices.contains(i) { continue }
//            let current = sortedDetections[i]
//            keptDetections.append(current)
//            
//            // Fixes Error 2: Safely converting Float coordinates to CGFloat explicitly for the CGRect spatial math loop
//            let currentRect = CGRect(
//                x: CGFloat(current.centerX - current.width / 2.0),
//                y: CGFloat(current.centerY - current.height / 2.0),
//                width: CGFloat(current.width),
//                height: CGFloat(current.height)
//            )
//            
//            for j in (i + 1)..<sortedDetections.count {
//                if ignoredIndices.contains(j) { continue }
//                let target = sortedDetections[j]
//                
//                let targetRect = CGRect(
//                    x: CGFloat(target.centerX - target.width / 2.0),
//                    y: CGFloat(target.centerY - target.height / 2.0),
//                    width: CGFloat(target.width),
//                    height: CGFloat(target.height)
//                )
//                
//                let intersection = currentRect.intersection(targetRect)
//                if !intersection.isNull {
//                    let intersectionArea = intersection.width * intersection.height
//                    let unionArea = (currentRect.width * currentRect.height) + (targetRect.width * targetRect.height) - intersectionArea
//                    let iou = intersectionArea / unionArea
//                    
//                    if iou > CGFloat(iouThreshold) {
//                        ignoredIndices.insert(j)
//                    }
//                }
//            }
//        }
//        return keptDetections
//    }
//}


// new CODE
import CoreML
import UIKit
import CoreImage

final class YOLODetector {

    private let model: best
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // 🎛️ ADJUST SENSITIVITY HERE
    private let confidenceThreshold: Float = 0.60
    private let iouThreshold: Float = 0.45 // Added default target overlap limit

    init?() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            model = try best(configuration: config)
        } catch {
            print("Failed to load model:", error)
            return nil
        }
    }

    /// Resizes a CVPixelBuffer to 640x640 using high-performance Core Image scaling
    private func resizePixelBuffer(_ srcBuffer: CVPixelBuffer, targetWidth: Int = 640, targetHeight: Int = 640) -> CVPixelBuffer? {
        let srcImage = CIImage(cvPixelBuffer: srcBuffer)
        let scaleX = CGFloat(targetWidth) / CGFloat(CVPixelBufferGetWidth(srcBuffer))
        let scaleY = CGFloat(targetHeight) / CGFloat(CVPixelBufferGetHeight(srcBuffer))
        
        let scaledImage = srcImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        var dstBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetWidth,
            targetHeight,
            kCVPixelFormatType_32BGRA,
            attrs,
            &dstBuffer
        )
        
        guard status == kCVReturnSuccess, let outputBuffer = dstBuffer else {
            return nil
        }
        
        ciContext.render(scaledImage, to: outputBuffer)
        return outputBuffer
    }

    func run(pixelBuffer: CVPixelBuffer) -> [Detection] {
        // 1. High-speed GPU Resize
        let resizeStart = CFAbsoluteTimeGetCurrent()
        guard let resizedBuffer = resizePixelBuffer(pixelBuffer) else {
            print("GPU Resize Failed")
            return []
        }
        let resizeTime = (CFAbsoluteTimeGetCurrent() - resizeStart) * 1000
        print(String(format: "GPU Buffer Resize Time: %.2f ms", resizeTime))

        // 2. Inference Loop
        do {
            let inferenceStart = CFAbsoluteTimeGetCurrent()
            
            // 🚀 FIXED: Explicitly providing the missing threshold parameters expected by best_3 architecture
            let input = bestInput(
                image: resizedBuffer,
                iouThreshold: Double(iouThreshold),
                confidenceThreshold: Double(confidenceThreshold)
            )
            
            let output = try model.prediction(input: input)

            let inferenceTime = (CFAbsoluteTimeGetCurrent() - inferenceStart) * 1000
            print(String(format: "Inference Time: %.2f ms", inferenceTime))

            let confidenceArray = output.confidence
            let coordinatesArray = output.coordinates
            
            guard let confPointer = try? UnsafeBufferPointer<Float32>(confidenceArray),
                  let coordPointer = try? UnsafeBufferPointer<Float32>(coordinatesArray) else {
                return []
            }
            
            let numDetections = coordinatesArray.shape[0].intValue
            let numClasses = confidenceArray.shape[1].intValue
            
            var detections: [Detection] = []
            let postProcessStart = CFAbsoluteTimeGetCurrent()
            
            for boxIndex in 0..<numDetections {
                var maxConfidence: Float = 0.0
                var bestClassIndex = 0
                
                let classRowOffset = boxIndex * numClasses
                for classIndex in 0..<numClasses {
                    let score = confPointer[classRowOffset + classIndex]
                    if score > maxConfidence {
                        maxConfidence = score
                        bestClassIndex = classIndex
                    }
                }
                
                if maxConfidence < confidenceThreshold { continue }
                
                let coordOffset = boxIndex * 4
                let relX = coordPointer[coordOffset + 0]
                let relY = coordPointer[coordOffset + 1]
                let relW = coordPointer[coordOffset + 2]
                let relH = coordPointer[coordOffset + 3]
                
                let centerX = relX * 640.0
                let centerY = relY * 640.0
                let width = relW * 640.0
                let height = relH * 640.0
                
                let className = bestClassIndex == 0 ? "white_buoy" : "target_object"
                
                let detection = Detection(
                    className: className,
                    confidence: maxConfidence,
                    centerX: centerX,
                    centerY: centerY,
                    width: width,
                    height: height
                )
                detections.append(detection)
            }
            
            let postProcessTime = (CFAbsoluteTimeGetCurrent() - postProcessStart) * 1000
            print(String(format: "Filtered Output Targets Count: %d | Post Process: %.2f ms", detections.count, postProcessTime))
            
            return detections

        } catch {
            print("Prediction error:", error)
            return []
        }
    }
}
