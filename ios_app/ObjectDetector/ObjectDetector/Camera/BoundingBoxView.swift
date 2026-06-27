import SwiftUI

struct BoundingBoxView: View {

    let detection: Detection

    var body: some View {
        GeometryReader { geo in
            // 1. Map the internal 640x640 inference layer dimensions onto the true device screen size
            let scaleX = geo.size.width / 640.0
            let scaleY = geo.size.height / 640.0

            // 2. Pure proportional scaling (No swaps!)
            let boxWidth = CGFloat(detection.width) * scaleX
            let boxHeight = CGFloat(detection.height) * scaleY

            // 3. THE WORKING FIX: Direct linear coordinate mapping
            let computedCenterX = CGFloat(detection.centerX) * scaleX
            let computedCenterY = CGFloat(detection.centerY) * scaleY

            // Render object bounding frame outline
            ZStack {
                Rectangle()
                    .fill(Color.red.opacity(0.05))

                Rectangle()
                    .stroke(Color.red, lineWidth: 2)
            }
            .frame(width: boxWidth, height: boxHeight)
            .position(x: computedCenterX, y: computedCenterY)

            // Render localized target centroid intercept point
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .position(x: computedCenterX, y: computedCenterY)
        }
    }
}
