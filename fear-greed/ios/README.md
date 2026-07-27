# iOS 端

## 目录结构

```
ios/
├── FearGreed.xcodeproj         工程（App + Widget Extension 两个 target）
├── FearGreedCore/              SwiftPM 包，全部业务代码都在这
│   ├── Sources/FearGreedCore/  模型 / 解码 / 展示格式化 / 端点常量
│   ├── Sources/FearGreedUI/    数据层 + SwiftUI 视图 + 小组件
│   └── Tests/                  41 个单测，`swift test` 即可跑
├── App/                        主 App target：@main 入口 + entitlements
├── Widget/                     Widget target：@main 入口 + entitlements + Info.plist
└── tools/RenderPreview/        把界面离屏渲染成 PNG 的开发工具
```

业务代码全部放在 SwiftPM 包里，Xcode target 只留 `@main`。这样做的直接好处：
**不装 Xcode 也能编译、单测、看到界面长什么样**，Xcode 只在真正需要跑模拟器/上架时才必需。

## 无 Xcode 时的验证方式

```bash
# 编译 + 41 个单测（Command Line Tools 即可）
cd fear-greed/ios/FearGreedCore && swift test

# 把界面渲染成 PNG（正常态 / 降级态 / 三种组件尺寸）
cd fear-greed/ios/tools/RenderPreview
swift run RenderPreview ../../FearGreedCore/Tests/FearGreedCoreTests/Fixtures/live_index.json /tmp/fg-preview
open /tmp/fg-preview
```

---

## 跑起来

工程已经建好并验证过，直接开：

```bash
open fear-greed/ios/FearGreed.xcodeproj
```

选 iPhone 模拟器 → `Cmd+R`。命令行等价写法：

```bash
cd fear-greed/ios
xcodebuild build -project FearGreed.xcodeproj -scheme FearGreed \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/fg-dd
xcrun simctl boot "iPhone 17"; open -a Simulator
xcrun simctl install booted /tmp/fg-dd/Build/Products/Debug-iphonesimulator/FearGreed.app
xcrun simctl launch booted com.quanxiaole.feargreed
```

### 工程配置速查

| 项 | 值 |
|---|---|
| App bundle ID | `com.quanxiaole.feargreed` |
| Widget bundle ID | `com.quanxiaole.feargreed.widget` |
| App Group | `group.com.quanxiaole.feargreed`（两个 target 都已配） |
| 最低系统 | iOS 17.0 |
| 依赖 | 本地 SwiftPM 包 `FearGreedCore`，两个 target 都链接 `FearGreedUI` 产物 |

App Group 字符串必须与 `Sources/FearGreedCore/Endpoint.swift` 里的 `appGroupID` 一致，
否则 App 与组件读不到同一份缓存。

### 已验证

- [x] `xcodebuild` 构建两个 target，零报错零警告
- [x] 模拟器运行，双市场卡片数值与[线上 index.json](https://raw.githubusercontent.com/quanxiaole/finapp/main/fear-greed/pipeline/out/index.json) 一致
- [x] 首次安装无缓存时能联网取数（证明 URLSession 链路通）
- [x] App Group 容器已创建、共享缓存文件已写入（证明 entitlement 生效）
- [x] `FearGreedWidget.appex` 正确嵌入 `FearGreed.app/PlugIns/`，扩展点为 `com.apple.widgetkit-extension`
- [ ] 把组件加到主屏 —— 需手动 3 步：长按主屏空白 → 左上角 `+` → 搜「恐慌指数」→ 选 Small/Medium → Add Widget

### 不需要做的事

- **不用改 Info.plist**：数据源是 HTTPS，不涉及 ATS 例外。
- **不用配后台刷新**：小组件由 WidgetKit 时间线驱动（30 分钟一次）。
- **不用付费开发者账号**：模拟器上 App Group 免费可用。真机调试与上架才需要（M3/M4）。

## 已知限制

- App Group 在**真机**上需要付费开发者账号签名，模拟器不受影响。
- 小组件刷新是「不早于 30 分钟」，系统会按电量与使用频率进一步节流，不是精确定时。
- A股指数的 `coverage` 目前是 0.65：`breadth` 与 `limit_sentiment` 两个因子受数据源限制只能向前累积历史，满两年前会一直显示低置信提示。
