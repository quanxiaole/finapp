import SwiftUI
import FearGreedUI

/// 主 App 入口。界面与数据逻辑都在 FearGreedUI 包里，
/// 这里只保留 Xcode target 必需的 @main 声明。
@main
struct FearGreedApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
    }
}
