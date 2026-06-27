import Foundation

struct USVLogger {
    /// Internal DateFormatter configured once for maximum performance in high-speed loops
    private static let formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        df.timeZone = TimeZone.current // Uses the local time zone of the device
        return df
    }()
    
    /// Generates a standardized, human-readable timestamp string (e.g., "2026-06-19 10:14:40.920")
    static var currentTimestamp: String {
        return formatter.string(from: Date())
    }
    
    /// Standardized logger for system milestones
    static func log(milestone: String, details: String = "") {
        let detailString = details.isEmpty ? "" : " -> \(details)"
        print("⏱️ [\(currentTimestamp)] [USV_LOG]: \(milestone)\(detailString)")
    }
}
