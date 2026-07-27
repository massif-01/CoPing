import CoPingCore
import Foundation

enum AppVersion {
    static var current: String {
        guard
            let version = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            !version.isEmpty
        else {
            return AppText.unknownVersion
        }
        return version
    }
}
