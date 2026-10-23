# Openly

**一屏看清 Mac 上「什么文件用什么打开」，顺手就能改。**

一个开源、原生、本地优先的 macOS 默认打开方式管理器。把散落在访达「显示简介」和系统设置深处的文件关联，收进一张可以搜索、可以批量改、可以反查、可以带走的表里。

![Status](https://img.shields.io/badge/status-v0.1.0-green) ![License](https://img.shields.io/badge/license-MIT-blue) ![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)

## 为什么

macOS 里改「双击 .md 用什么打开」，只有两条路：右键 → 显示简介 → 打开方式（一次一个扩展名，还埋在二级菜单里），或者系统设置 → 桌面与程序坞 → 默认网页浏览器（只管浏览器和邮件）。

没有的是**总览**：我这台机器上到底有哪些关联、哪些类型压根没有默认应用、某个应用悄悄接管了多少种文件。也没有**批量**：换了编辑器，要一个个去改十几个扩展名。更没有**迁移**：换台电脑，全部重来一遍。

Openly 把这件事做成一张表。

## 特性

- **一屏总览** — 首屏把「你在系统里设置过的关联」（Launch Services 的 secure plist）和一份常用扩展名清单合并成一张表：`.md`、`.pdf`、`.html`、`mailto:`、`plain-text` 都在里面。每行是类型徽标、UTI、默认应用的真实图标、注册应用数，一次加载后常驻内存
- **点一行就改** — 任意一行点开是一个锚定在被点击行上的 popover，列出注册过这个类型的所有应用（图标 + 名称 + bundle ID），选一个即生效；行内图标当场更新，底部浮出「.md → Typora ✓」
- **列表里没有的应用也能用** — 「浏览其他应用…」打开系统选择器任选一个 `.app`，先注册进 Launch Services 再设为默认，不必非得在 `/Applications` 下
- **批量修改** — 行前勾选（支持全选当前视图），底部浮出批量操作条；候选应用取所选行注册应用的并集，一次应用到全部。应用不声明支持的类型逐条跳过并汇总报出，不会中途断掉
- **按应用反查** — 顶部分段控件切到「按应用」：侧栏按接管数量排出所有应用，主区列出它手里每一个类型，还能一键「全部转移给…」。卸载或换掉一个应用之前，先看清它管着什么
- **智能列表** — 全部关联 / 无默认应用（红色「无默认」徽标，一眼看到哪些类型没人管）/ 最近修改（每次改动的「原为 X → Y」都记着，写进本机 UserDefaults，重启还在，最多 50 条）
- **搜索与分类** — 工具栏搜索框匹配扩展名、UTI、默认应用名；侧栏按 UTType 继承关系分文档 / 图片 / 音频 / 视频 / 归档 / 源代码 / 系统七类，外加独立的 URL Scheme 分类
- **TOML 导入导出** — 导出当前全部关联为 infat 兼容的 TOML（`[extensions]` `[types]` `[schemes]` 三张表），可直接放进 dotfiles；导入先算差异——新增 N 条、覆盖 M 条、其余一致——确认后才动手，改之前你就知道会改什么
- **键盘可用** — `↑` `↓` 在列表里上下移动，`↩` 打开当前行的应用选择器
- **看起来是系统的一部分** — SwiftUI + `NavigationSplitView`，应用图标直接取 `NSWorkspace` 真实图标，跟随浅色 / 深色与系统强调色
- **内核可复用** — `LaunchServicesKit` 是一个不含 UI 依赖的独立 Swift Package，GUI 与自带的 `lsk` 命令行工具共用同一套逻辑，也可以直接拿去写脚本或别的 App
- **零第三方依赖** — 不引 TOML 库，编解码自己写；27 项单元测试；GitHub Actions 双系统（macOS 15 / 26）CI

## 安装

从 [Releases](https://github.com/TonyMistark/openly/releases) 下载最新的 `Openly-<版本>.dmg`，打开后把 Openly 拖进「应用程序」。

本仓库没有 Developer ID 证书，产物是 **ad-hoc 签名、未公证**，新机器首次打开会被 Gatekeeper 拦下（macOS 15 起已不能用「右键 → 打开」绕过）：

- 系统设置 › 隐私与安全性 › 仍要打开；或
- `xattr -cr /Applications/Openly.app` 后再打开

## 快速开始

1. 打开 Openly，首屏就是全部关联。左栏点「无默认应用」，看看哪些类型没人管
2. 点任意一行，在弹出的应用列表里换一个默认应用。系统会弹一次确认框，点「使用」
3. 顶栏切到「按应用」，看看你新装的编辑器接管了多少种文件
4. 工具栏「导出」，把这份配置存进 dotfiles；换机器时用「导入」还原，先看差异再应用

命令行验证工具（与 GUI 同源，语义对齐 infat）：

```shell
swift run lsk info --ext md          # 查看 .md 的默认与全部注册应用
swift run lsk dump                   # 列出 Launch Services 里全部 handler
swift run lsk supertypes             # 列出 24 种回退类型
swift run lsk app "Safari"           # 名称 → 路径 / bundle ID
```

## 打包

```shell
./make-app.sh          # → dist/Openly.app（默认用机器上第一枚可用证书签名）
./make-dmg.sh          # → dist/Openly-<版本>.dmg（对外分发，ad-hoc 签名）
```

版本号优先取 `OPENLY_VERSION`，否则取最近一个 git tag。需要 Developer ID 时：

```shell
OPENLY_SIGN_IDENTITY="Developer ID Application: …" ./make-dmg.sh
```

## 设计哲学

- **原生优先** — 系统控件、系统图标、系统配色。看起来应该像苹果自己写的那个「默认应用」面板
- **每一次点击都说得清** — GUI 的每个操作都对应一条可复现的语义（`.md` → 某个 bundle ID），不做黑箱批量魔法；导入前先给你差异，改完给你回执
- **不藏危险动作** — 只改你点过的东西。没有「一键优化」这类会莫名其妙动你系统的按钮

## 已知限制

- **每次改默认都会弹一次系统确认** — macOS 26 起的系统行为，GUI 绕不过去，批量修改就是多次确认。这也是为什么批量操作会提前告诉你「系统会逐项弹确认框」
- **`⌘Z` 撤销与「恢复系统默认」还没做** — 目前只能再手动改回去
- **异常检测只做了「无默认」** — 「非常规占用」（比如 .html 被非浏览器接管）和「共享 UTI 联动提示」（yml / yaml 改一个影响另一个）在计划里
- **不上架 App Store** — 沙盒会拦住 Launch Services 写入，只能 Developer ID 直发
- **外部改动不会自动出现** — Launch Services 没有变更通知，别的程序改了关联之后，按一下工具栏的刷新

## 路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| M0 | LaunchServicesKit：查询 / 设置 / plist 解析 + 单元测试 | ✅ 完成 |
| M1 | 三栏 UI + 总览 + 搜索 + 单条修改 + toast | ✅ 完成 |
| M2 | 批量修改 + 按应用反查 + 智能列表 | ✅ 完成 |
| M3 | TOML 导入导出 + 差异预览 | ✅ 完成 |
| M3 | `⌘Z` 撤销 + 恢复系统默认 | ⬜ 待做 |
| M4 | 异常检测（非常规占用 / 共享 UTI）+ 设置窗口 | ⬜ 待做 |
| M4 | 图标、空状态、公证与 Homebrew cask | 🚧 部分完成 |

详细规格见 [`docs/PRODUCT.md`](docs/PRODUCT.md)，里程碑拆解见 [`docs/ROADMAP.md`](docs/ROADMAP.md)，macOS 26 上踩到的 Launch Services 坑记在 [`docs/LAUNCHSERVICES_NOTES.md`](docs/LAUNCHSERVICES_NOTES.md)。

## 参与贡献

```shell
swift build --disable-sandbox
swift test --disable-sandbox
```

改 `LaunchServicesKit` 的查询逻辑时，记得对照 `infat info` 的输出验证——它是这套语义的参照系。

## 协议

MIT。见 [LICENSE](LICENSE)。

## 致谢

- [infat](https://tangled.org/did:plc:w45df32pddkw6yywbsrl5r2u/infat) —— 这个项目的起点。它用 CLI 证明了这些能力在 macOS 上都做得成，TOML 配置格式也直接沿用
- [duti](https://github.com/moretension/duti) —— 更早的那一个
- Apple，为这些能力留了公开 API，只是文档写得很省
