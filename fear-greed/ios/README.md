# iOS 端

## 目录结构

```
ios/
├── FearGreedCore/              SwiftPM 包，全部业务代码都在这
│   ├── Sources/FearGreedCore/  模型 / 解码 / 展示格式化 / 端点常量
│   ├── Sources/FearGreedUI/    数据层 + SwiftUI 视图 + 小组件
│   └── Tests/                  41 个单测，`swift test` 即可跑
├── App/FearGreedApp.swift      主 App 入口（加进 Xcode App target）
├── Widget/FearGreedWidgetBundle.swift  组件入口（加进 Widget target）
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

## 建 Xcode 工程（M2b）

装好 Xcode 后按下面步骤操作。全程约 10 分钟。

### 1. 新建工程

`File → New → Project… → iOS → App`，填：

| 字段 | 值 |
|---|---|
| Product Name | `FearGreed` |
| Organization Identifier | `com.quanxiaole` |
| Interface | SwiftUI |
| Language | Swift |
| Storage | None |
| Include Tests | 不勾（单测在 SwiftPM 包里） |

保存位置选 `finapps/fear-greed/ios/`，**不要**勾 Create Git repository（仓库已在 `finapps` 根）。

建完把 Deployment Target 改成 **iOS 17.0**（选中 project → target `FearGreed` → General → Minimum Deployments）。

### 2. 加 Widget Extension

`File → New → Target… → iOS → Widget Extension`：

- Product Name: `FearGreedWidget`
- **取消勾选** Include Configuration App Intent（MVP 用静态组件，不做配置界面）
- 弹出 "Activate scheme?" 选 **Activate**

### 3. 两个 target 都加 App Group

对 `FearGreed` 和 `FearGreedWidget` **各做一次**：

选中 target → `Signing & Capabilities` → `+ Capability` → 搜 `App Groups` → 点 `+` 添加：

```
group.com.quanxiaole.feargreed
```

这个字符串必须与 `Sources/FearGreedCore/Endpoint.swift` 里的 `appGroupID` 完全一致，否则 App 与组件读不到同一份缓存。

### 4. 引入本地 SwiftPM 包

`File → Add Package Dependencies… → Add Local…`，选 `fear-greed/ios/FearGreedCore` 目录。

然后给**两个 target** 都链接产物：target → General → Frameworks, Libraries, and Embedded Content → `+` → 选 `FearGreedUI`（它会自动带上 `FearGreedCore`）。

### 5. 替换入口文件

Xcode 会自动生成一批模板文件，删掉这些：

- `FearGreed/ContentView.swift`
- `FearGreed/FearGreedApp.swift`
- `FearGreedWidget/FearGreedWidget.swift`
- `FearGreedWidget/AppIntent.swift`（如果有）

然后把仓库里写好的两个入口文件拖进去（勾 Copy items if needed，注意 Target Membership 别选错）：

| 文件 | 加到哪个 target |
|---|---|
| `ios/App/FearGreedApp.swift` | `FearGreed` |
| `ios/Widget/FearGreedWidgetBundle.swift` | `FearGreedWidget` |

### 6. 跑起来

选模拟器（iPhone 15 及以上，iOS 17+）→ `Cmd+R`。

验收清单：

- [ ] 主 App 显示美股 / A股两张卡片，数值与 [线上 index.json](https://raw.githubusercontent.com/quanxiaole/finapp/main/fear-greed/pipeline/out/index.json) 一致
- [ ] 下拉可刷新，更新时间跟着变
- [ ] 长按主屏 → 编辑 → 添加组件，能看到「A股 / 美股 / 双市场 恐慌指数」三项
- [ ] Small 与 Medium 加到主屏，数值与主 App 一致
- [ ] 关掉网络（模拟器 → Features → Network Link Conditioner，或直接断开 Mac 网络）重开 App，仍显示上次数据 + 「刷新失败」提示，不白屏

### 不需要做的事

- **不用改 Info.plist**：数据源是 HTTPS，不涉及 ATS 例外。
- **不用配后台刷新**：小组件由 WidgetKit 时间线驱动（30 分钟一次）。
- **不用付费开发者账号**：模拟器上 App Group 免费可用。真机调试与上架才需要（M3/M4）。

## 已知限制

- App Group 在**真机**上需要付费开发者账号签名，模拟器不受影响。
- 小组件刷新是「不早于 30 分钟」，系统会按电量与使用频率进一步节流，不是精确定时。
- A股指数的 `coverage` 目前是 0.65：`breadth` 与 `limit_sentiment` 两个因子受数据源限制只能向前累积历史，满两年前会一直显示低置信提示。
