# Launch Services 工程笔记

macOS 上「改默认打开方式」这件事，公开 API 旧、文档薄、行为随系统版本变。这份笔记记下实测结论与踩过的坑，免得下次重新踩一遍。

测试环境：macOS 26（Tahoe），arm64。对照实现：infat 0.1.x（Rust）。

---

## 1. 结论速览

| 操作 | API | macOS 14 / 15 | macOS 26 |
|---|---|---|---|
| 查询默认应用 | `LSCopyDefaultRoleHandlerForContentType` | ✅ | ✅ |
| 查询全部注册应用 | `LSCopyAllRoleHandlersForContentType` | ✅ | ✅ |
| 查询 scheme | `LSCopyDefaultHandlerForURLScheme` / `LSCopyAllHandlersForURLScheme` | ✅ | ✅ |
| **设置默认应用** | `LSSetDefaultRoleHandlerForContentType` | ✅ | ❌ 返回 `noErr` 但**不写入** |
| **设置 scheme** | `LSSetDefaultHandlerForURLScheme` | ✅ | ❌ 同上 |
| **设置默认应用** | `NSWorkspace.setDefaultApplication(at:toOpen:)` | ✅ | ✅（需用户确认） |

一句话：**在 macOS 26 上，查询仍然走 legacy C API，设置必须走 NSWorkspace。**

## 2. legacy set API 静默失效

```swift
// macOS 26：status == noErr，但 plist 里什么都没变，读回还是老值
let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, .viewer, bundleID as CFString)
```

这个坑最麻烦的地方是它**不报错**。任何「调完 API 就当成功」的实现都会给用户一个假回执。

对策：设置之后一定读回验证。

```swift
let readBack = try? defaultApp(forUTI: uti)
guard readBack == bundleID else { throw LSKError.launchServicesFailed("did not take effect") }
```

`infat` 本身在这台机器上同样失效——不是它写错了，是 API 层面变了。

## 3. NSWorkspace 现代 API

```swift
try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: contentType)        // UTType
try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: s)    // URL scheme
```

几个签名细节：

- ObjC 头文件里叫 `setDefaultApplicationAtURL:toOpenContentType:completionHandler:`，Swift 导入后是 **`toOpen:`**，不是 `toOpenContentType:`
- **completion 版本没有被导入**，只有 async 版本。要同步调用得用 `Task` + `DispatchSemaphore` 包一层（见 `LSKAssociation.setDefaultAppNSWorkspace`）
- 传的是应用 **URL**，不是 bundle ID。bundle ID 得先经 `NSWorkspace.urlForApplication(withBundleIdentifier:)` 解析成路径

## 4. macOS 26 的系统确认弹窗

改默认应用时系统会弹出确认框（「Openly 想要更改 .md 的默认应用」）。这带来三件事：

1. **headless 进程必然失败**：拿不到 UI 就自动取消，报 `NSError`，`NSCocoaErrorDomain` code 256，`NSUnderlyingErrorKey` 里是 `userCanceledErr`(-128)。代码里 `isUserCancelled` 就是认这个特征
2. **批量修改 = 多次确认**：一次 set 一次弹窗。所以批量操作必须在文案里提前说清楚，否则用户会以为程序卡住了
3. **infat 式的「一条命令改默认」在新系统上已经不可行**：CLI 没有 UI 去接这个弹窗。这不是 Openly 的问题，是 macOS 的策略变化

现在 `setDefaultAppViaNSWorkspace` 的顺序是：NSWorkspace 设置 → 读回验证 → 失败则回退 legacy → 再读回验证 → 仍不对就抛错。宁可报错，不要假成功。

## 5. 特例路由表

macOS 的关联不是「一个扩展名一个 handler」这么直白。以下几条必须特判，否则会出现「改了没反应」：

| 情况 | 实际行为 | 处理 |
|---|---|---|
| `.html` | 由 `http` URL scheme 的 handler 控制 | `setDefaultApp(ext: "html")` → 转发到 `scheme: "http"` |
| `https` | 与 `http` 共享同一个 handler | 统一按 `http` 处理 |
| `public.html` / `com.apple.default-app.web-browser` | 浏览器类型，实际落在 http scheme | 转发到 `http` |
| `yml` / `yaml` | 共享同一个 UTI，改一个影响另一个 | 目前靠读回验证暴露；UI 提示待做 |

`LSKAssociation.uti(forExtension:)` 里对 infat 的行为做了一处刻意对齐：**SuperType 能解析的扩展名直接用它的 UTI，不走 `UTType` 推导**。这让 `.html` 稳定映射到 `public.html`。

## 6. 级联解析（cascading resolution）

macOS 找 handler 的顺序是：

```
具体格式标识符（扩展名 / 精确 UTI）
        ↓ 没有
父类型（plain-text / image / …）
        ↓ 没有
更上层类型
```

所以「按类型设置」（`--type plain-text`）是**回退值**，优先级低于任何扩展名的具体设置。UI 上如果不说明这一点，用户会疑惑「我明明设了 plain-text 用 VSCode，为什么 .md 还是 Typora」。

## 7. secure plist 的结构

路径：

```
~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist
```

根字典里 `LSHandlers` 是一个数组，每条记录可能带这些键：

| 键 | 含义 |
|---|---|
| `LSHandlerContentTag` + `LSHandlerContentTagClass` | 扩展名（class = `public.filename-extension`） |
| `LSHandlerURLScheme` | URL scheme |
| `LSHandlerContentType` | UTI（可能是 `public.plain-text` 这种回退类型） |
| `LSHandlerRoleAll` / `LSHandlerRoleViewer` / `LSHandlerRoleEditor` | 处理应用，优先级 all > viewer > editor |

两个重要事实：

- **这个 plist 只包含「用户显式设置过」的关联**，不是系统支持的全部类型。所以首屏总览必须额外补一份常用扩展名清单，否则新机器上只有寥寥几行
- **无默认应用的类型无法枚举**。没有「列出所有已知 UTI」的 API。只能靠 plist ∪ 推荐清单 ∪ 搜索时动态查询（`UTTypeCreatePreferredIdentifierForTag` 对未知扩展名会生成 `dyn.*` 动态 UTI）

## 8. 没有变更通知

Launch Services 不提供「关联已变更」的通知。别的程序（或用户在访达里）改了关联，列表不会自己更新。

现有对策：工具栏手动刷新 + 应用回到前台时重载。更好的做法是监听 plist 的修改时间（`NSFilePresenter` 或 `DispatchSource` 文件事件），目前没做。

## 9. 沙盒与 App Store

`NSWorkspace.setDefaultApplication` 和 legacy LS 写入在 App Sandbox 下都会被拒。所以：

- 不上架 App Store
- 不用开启 App Sandbox
- Developer ID 直发 + 公证 + Homebrew cask 是唯一路径

## 10. 验收方法

`lsk` 工具与 GUI 共用同一套库，语义对齐 infat：

```shell
swift run lsk info --ext md
swift run lsk dump                    # 全部 handler
swift run lsk supertypes              # 24 种回退类型
```

M0 的验收标准是「`lsk info --ext x` 与 `infat info --ext x` 输出一致」。**查询侧这条标准今天仍然成立；设置侧已经不成立**——infat 在 macOS 26 上改不动，只能用 Openly 的 GUI 手动验证。
