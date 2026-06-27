import Foundation

// 1. Add ': Identifiable' to the struct definition
struct Detection: Identifiable {
    
    // 2. Add a unique tracking identifier
    let id = UUID()

    let className: String
    let confidence: Float

    let centerX: Float
    let centerY: Float

    let width: Float
    let height: Float

    var left: Float {
        centerX - width / 2
    }

    var right: Float {
        centerX + width / 2
    }

    var top: Float {
        centerY - height / 2
    }

    var bottom: Float {
        centerY + height / 2
    }
}

extension Detection {

    static let empty = Detection(
        className: "None",
        confidence: 0,
        centerX: 0,
        centerY: 0,
        width: 0,
        height: 0
    )
}
