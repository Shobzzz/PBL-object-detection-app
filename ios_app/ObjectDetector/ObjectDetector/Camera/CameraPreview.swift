//
//  CameraPreview.swift
//  ObjectDetector
//

import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(
        context: Context
    ) -> PreviewView {

        let view = PreviewView()

        view.previewLayer.session = session

        view.previewLayer.videoGravity =
            .resizeAspectFill

        if let connection =
            view.previewLayer.connection {

            connection.videoRotationAngle = 0
        }

        return view
    }

    func updateUIView(
        _ uiView: PreviewView,
        context: Context
    ) {
    }
}

final class PreviewView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {

        super.layoutSubviews()

        previewLayer.frame = bounds


        print(
            "PREVIEW BOUNDS:",
            bounds.width,
            bounds.height
        )

        if let connection = previewLayer.connection {

            connection.videoRotationAngle = 0

            print(
                "PREVIEW ROTATION AFTER SET:",
                connection.videoRotationAngle
            )
        }
    }
}
