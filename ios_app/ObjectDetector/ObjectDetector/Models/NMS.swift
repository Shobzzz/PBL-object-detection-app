//
//  NMS.swift
//  ObjectDetector
//
//  Created by 九州工業大学　石井研究室アプリサービス係 on 07/06/26.
//
import Foundation

func intersectionOverUnion(
    _ a: Detection,
    _ b: Detection
) -> Float {

    let x1 = max(a.left, b.left)
    let y1 = max(a.top, b.top)

    let x2 = min(a.right, b.right)
    let y2 = min(a.bottom, b.bottom)

    let intersectionWidth =
        max(0, x2 - x1)

    let intersectionHeight =
        max(0, y2 - y1)

    let intersectionArea =
        intersectionWidth * intersectionHeight

    let areaA =
        a.width * a.height

    let areaB =
        b.width * b.height

    let unionArea =
        areaA + areaB - intersectionArea

    if unionArea <= 0 {
        return 0
    }

    return intersectionArea / unionArea
}

func nonMaximumSuppression(
    detections: [Detection],
    iouThreshold: Float = 0.5
) -> [Detection] {

    let sorted =
        detections.sorted {
            $0.confidence > $1.confidence
        }

    var kept: [Detection] = []

    for detection in sorted {

        var shouldKeep = true

        for existing in kept {

            let iou =
                intersectionOverUnion(
                    detection,
                    existing
                )

            if iou > iouThreshold {

                shouldKeep = false
                break
            }
        }

        if shouldKeep {
            kept.append(detection)
        }
    }

    return kept
}
