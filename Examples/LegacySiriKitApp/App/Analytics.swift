import Foundation
import AppTrackingTransparency

/// Tracking consent, which now also needs a PrivacyInfo.xcprivacy manifest.
enum Analytics {
    static func requestConsent() {
        ATTrackingManager.requestTrackingAuthorization { status in
            enabled = (status == .authorized)
        }
    }

    static var enabled = false
}
