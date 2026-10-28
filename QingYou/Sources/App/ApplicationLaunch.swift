import AppKit
import CoreServices

enum ApplicationLaunch {
    static func showsSettings(arguments: [String], event: NSAppleEventDescriptor?) -> Bool {
        // 冷启动时，请求文件可能晚于启动通知到达；用启动参数识别来源，不靠延时猜测。
        if arguments.contains(Product.finderLaunchArgument) { return false }
        if LoginItemController.isLoginLaunch(event) { return false }
        if event?.eventClass == AEEventClass(kCoreEventClass),
           event?.eventID == AEEventID(kAEOpenDocuments) { return false }
        return true
    }
}
