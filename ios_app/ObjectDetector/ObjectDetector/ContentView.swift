import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    
    // CONFIGURABLE CONNECTION TARGETS
    @State private var targetRobotIP = "192.168.2.1"
    @State private var targetiPadIP = "192.168.2.194"

    var body: some View {
        ZStack(alignment: .topTrailing) { // Aligns overlays to the top right
            
            // 1. Full screen raw camera video stream background
            CameraPreview(session: cameraManager.session)
                .edgesIgnoringSafeArea(.all)
            
            // 2. Continuous tracking overlays (Bounding boxes and center reticle)
            GeometryReader { displayGeo in
                ForEach(cameraManager.detections) { detection in
                    BoundingBoxView(detection: detection)
                }
                
                // Static Center Sight Overlay to aid physical USV lens calibration
                TargetCrosshairView(screenSize: displayGeo.size)
            }
            .edgesIgnoringSafeArea(.all)
            
            // 🛠️ Double-Sized Circular Hardware Restart Button (96x96 points)
            Button(action: {
                cameraManager.rebuildNetworkPipelines(robotIP: targetRobotIP, ipadIP: targetiPadIP)
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 32, weight: .bold))
            }
            .buttonStyle(LargeRestartButtonStyle())
            .padding(.top, 16)
            .padding(.trailing, 8) // Precise padding constraint from the physical screen bezel
        }
        .background(Color.black)
        .onAppear {
            USVLogger.log(milestone: "APP_INITIALIZATION", details: "Core UI elements bound.")
            cameraManager.startSession()
            
            // 🚀 FIXED: Stagger the network pipelines initialization by 600ms.
            // This leaves an open window for the local hardware to acquire IPs, resolve subnets,
            // and spin up routing targets before pushing active TCP handshakes out over the airwaves.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                cameraManager.rebuildNetworkPipelines(robotIP: targetRobotIP, ipadIP: targetiPadIP)
            }
        }
    }
}

// =========================================================================
// MARK: - Custom Button Style for Large Circular Reboot Interface (96x96)
// =========================================================================
struct LargeRestartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 96, height: 96)
            .foregroundColor(configuration.isPressed ? .black : .white.opacity(0.3))
            .background(
                configuration.isPressed ?
                Color.yellow :
                Color(white: 0.2).opacity(0.2)
            )
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(configuration.isPressed ? Color.yellow : Color.white.opacity(0.15), lineWidth: 2.5)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// A simple UI crosshair representing the exact center (0,0) of the system
struct TargetCrosshairView: View {
    let screenSize: CGSize
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                .frame(width: 40, height: 40)
            
            Rectangle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 2, height: 15)
            
            Rectangle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 15, height: 2)
        }
        .position(x: screenSize.width / 2, y: screenSize.height / 2)
    }
}
