import WidgetKit
import SwiftUI
import FearGreedUI

/// Widget Extension 入口。三个组件的实现都在 FearGreedUI 包里。
@main
struct FearGreedWidgetBundle: WidgetBundle {
    var body: some Widget {
        CNIndexWidget()
        USIndexWidget()
        DualMarketWidget()
    }
}
