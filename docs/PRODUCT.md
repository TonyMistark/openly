# Openly — 产品文档

> 一个 macOS 默认打开方式管理器。基于 [infat](https://tangled.org/did:plc:w45df32pddkw6yywbsrl5r2u/infat) 的能力模型，用 SwiftUI 重做成原生 GUI。

---

## 1. 产品故事

macOS 上「某个文件用什么打开」这件事，系统给了两个入口，都不好用。

第一个在访达里：右键 → 显示简介 → 打开方式 → 选应用 → 点「全部更改」。一次只能改一个扩展名，路径埋两级，改完关掉就再也想不起来上次改的是哪个。

第二个在系统设置里：只有「默认网页浏览器」和「默认邮件阅读器」两项。浏览器和邮件之外的所有类型——.md、.pdf、.png、.mp4、.json——系统当你不需要管。

于是出现几种典型的难受：

- 换了 Markdown 编辑器，要一个个扩展名去改 `.md`、`.markdown`、`.mdown`
- 想知道「这台机器上还有哪些类型没有默认应用」，没有任何地方能看
- 想卸载一个应用，不知道它现在接管着哪些文件，卸完发现几十个类型打不开了
- 换新电脑，所有关联重来一遍

`infat` 这个 Rust CLI 已经证明这些能力在技术上全部可行——它直接读 Launch Services 数据库、调 LS API，用一条命令就能改默认应用，还能把全部关联写进 TOML 放进 dotfiles。

缺的只是一张脸。Openly 就是这张脸。

## 2. 设计哲学

**原生优先。** SwiftUI + 系统控件 + 真实应用图标。它应该看起来像苹果自己会写的那个「默认应用」面板，而不是一个套了壳的网页。

**每一次点击都说得清。** 每个 GUI 操作都对应一条可复现的语义（`.md` → `abnerworks.Typora`）。导入配置前先给你差异，改完给你回执。不做「一键优化」这种会莫名其妙动你系统的按钮。

**只改你点过的东西。** 没有后台扫描改写，没有隐式的批量修正。危险动作永远在用户眼前发生。

## 3. 目标用户

- **重度 Mac 用户**：装了很多同类应用（三个编辑器、两个浏览器、两个看图工具），需要明确指定谁管什么
- **开发者 / dotfiles 用户**：希望文件关联和 `.zshrc` 一样可版本控制，换机器一条命令还原
- **infat 的现有用户**：命令行改不动的那部分（总览、反查、异常发现）交给 GUI

## 4. 功能规格

### F1 · 关联总览（首屏）

列出系统中所有已定义的关联：

| 列 | 内容 |
|---|---|
| 勾选框 | 批量选择 |
| 类型徽标 + 主标识 | 扩展名 `.md` / scheme `mailto:` / 类型 `plain-text` |
| 副标题 | 底层 UTI（`net.daringfireball.markdown`） |
| 默认应用 | 真实图标，悬浮显示名称与路径；无默认时显示红色「无默认」 |
| 注册数 | 有多少应用注册了该类型 |

数据来源是三层兜底：Launch Services secure plist（用户显式设置过的）∪ 常用扩展名清单（约 50 项）∪ 搜索时的动态查询。冷启动一次全量加载，之后走内存。

### F2 · 搜索与筛选

工具栏搜索框匹配扩展名、UTI、默认应用名。侧栏两组过滤：

- **智能列表**：全部关联 / 无默认应用 / 最近修改
- **文件类别**：文档、图片、音频、视频、归档、源代码、系统，外加 URL Scheme。分类基于 UTType 的继承关系（`conforms(to:)`）推导，不是硬编码映射表

### F3 · 单条修改

点击任意一行 → 锚定在该行的 popover：

- 列出全部注册应用（图标 + 名称 + bundle ID），当前默认打勾
- 选中即生效，popover 关闭，行内图标更新，底部浮出 toast
- 「浏览其他应用…」→ NSOpenPanel 任选 `.app` → `LSRegisterURL` 注册 → 设为默认
- macOS 26 起系统会弹一次确认框，文案在操作前就告知用户

### F4 · 批量修改

勾选多行（支持全选当前视图）→ 底部浮出批量条 →「设为默认应用…」→ sheet 里选应用。

候选应用是所选行注册应用的**并集**。执行时逐条进行：成功计数、应用不支持的类型计入「跳过」、其余计入「失败」，最后一条 toast 汇总，不中途中断。

### F5 · 按应用反查

顶部分段控件切到「按应用」：

- 侧栏：所有正在担任默认应用的应用，按接管数量降序
- 主区：该应用的 hero（图标、名称、bundle ID、接管数量）+ 它手里的每一个类型
- 「全部转移给…」：把这批类型一次性交给另一个应用

场景很具体：卸载或替换一个应用之前，先看清它管着什么。

### F6 · 智能列表（异常检测）

| 列表 | 判定 | 状态 |
|---|---|---|
| 无默认应用 | `defaultApp == nil` | ✅ |
| 最近修改 | 本次 / 历史改动记录（本机持久化，上限 50） | ✅ |
| 非常规占用 | 如 .html 被非浏览器接管、.pdf 被脚本工具接管 | ⬜ 计划中 |
| 共享 UTI 提示 | yml / yaml 改一个影响另一个，行内 ⚠ | ⬜ 计划中 |

### F7 · 配置导入 / 导出

- **导出**：当前全部关联 → infat 格式 TOML，三张表 `[extensions]` `[types]` `[schemes]`。可拷贝或存盘，直接进 dotfiles
- **导入**：选 TOML → 解析 → 与当前状态对比 → 差异 sheet（新增 N 条 / 覆盖 M 条 / 其余一致）→ 确认后按应用分组批量执行

### F8 · 撤销与恢复（计划中）

- `⌘Z` 单步撤销：每次 set 之前记录旧值
- 「恢复系统默认」：把某类型交还给系统原本的 handler

### 4.1 明确不做（v1）

- 不做「这一次用某应用打开」（非默认的一次性打开），那是访达的领域
- 不做 iOS / iPadOS
- 不上架 App Store（沙盒会拦住 Launch Services 写入）
- 不做跨机器的配置同步服务——配置文件交给 git

## 5. 界面结构

```
┌──────────────────────────────────────────────────────────────┐
│  Openly        [按类型 | 按应用]   🔍搜索     导出 导入 刷新  │
├───────────┬──────────────────────────────────────────────────┤
│ 智能列表   │  ☐ │ .md       net.daringfireball… │ ▢ Typora    │
│  全部 312  │  ☐ │ .pdf      com.adobe.pdf       │ ▢ 预览      │
│  无默认 8  │  ☐ │ .html     public.html          │ ▢ Safari    │
│  最近修改  │  …                                               │
│ 文件类别   │                                                  │
│  文档/图片 │                                                  │
│  …        │                                                  │
│ 链接协议   │                                                  │
├───────────┴──────────────────────────────────────────────────┤
│        （多选时浮出）已选 5 项  [设为默认应用…]  [取消选择]    │
└──────────────────────────────────────────────────────────────┘
```

视觉规范：

- 列表行紧凑（约 36pt），交替行背景
- 类型徽标按分类着色：文档蓝、图片橙、音频粉、视频红、归档紫、代码绿、系统灰、scheme 青
- 应用图标直接取 `NSWorkspace.shared.icon(forFile:)`，不缓存不重绘
- 跟随系统浅色 / 深色 / 强调色，没有自建主题系统

交互原型见 [`prototype.html`](prototype.html)（早期 HTML 稿，用于确认信息架构，与最终实现有差异）。

## 6. 技术方案

### 6.1 栈

| 层 | 选型 |
|---|---|
| UI | SwiftUI（macOS 14+），`NavigationSplitView` 三栏、popover、sheet |
| 核心 | 纯 Swift 调 CoreServices / LaunchServices / UniformTypeIdentifiers 的 C 与 Swift API |
| 数据 | 内存模型 + 自写 TOML 编解码（无第三方库） |
| 持久化 | 最近修改记录存 UserDefaults（JSON） |
| 分发 | SPM 构建 → 手工组装 .app → 签名 → DMG |

### 6.2 分层

```
Sources/
├── LaunchServicesKit/          # 无 UI 依赖，可独立复用
│   ├── LSKAssociation.swift    # 查询 / 设置（含 html→http 等特例路由）
│   ├── LSKDatabase.swift       # secure plist 解析（全量 handler 清单）
│   ├── LSKAppResolver.swift    # bundleID ↔ 名称 / 路径 / 图标
│   ├── LSKSupertypes.swift     # 24 种回退类型表（移植自 infat）
│   ├── TOMLConfig.swift        # infat 兼容配置编解码
│   ├── Models.swift
│   └── Errors.swift
├── LSKTool/                    # lsk 命令行工具：info / set / dump / supertypes / app
└── Openly/                     # SwiftUI 应用
    ├── AssociationStore.swift  # ObservableObject：加载、过滤、修改、批量
    ├── ContentView.swift       # 三栏 + 列表 + popover + 批量条 + 按应用视图
    ├── ConfigIO.swift          # 导出 / 导入差异 / 最近修改持久化
    └── ConfigSheets.swift      # 导出 sheet、差异 sheet、文件选择
```

关键取舍：

- **不混编 Rust**。infat 的核心逻辑约 1000 行 Rust，调的全是公开 C API，用 Swift 重写成本远低于维护两套工具链
- **`LaunchServicesKit` 与 UI 严格分离**，`lsk` 工具只依赖它，GUI 也只依赖它。库能单独发出去
- **单行刷新**。改完一行只重查那一行，不整表 reload，避免列表闪烁

### 6.3 数据模型

```swift
enum AssociationKind { case fileExtension(String), superType(SuperType), urlScheme(String), uti(String) }

struct AssociationRow: Identifiable {
    let kind: AssociationKind
    let displayID: String       // ".md" / "mailto:" / "plain-text"
    let uti: String?
    var defaultApp: AppRef?     // nil = 无默认
    var registered: [AppRef]
    let category: Category
}

struct AppRef: Identifiable {
    let bundleID: String
    let name: String
    let path: String?
}
```

## 7. 路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| M0 | LaunchServicesKit + 27 项单元测试，对照 infat 语义验收 | ✅ |
| M1 | 三栏 UI、总览、搜索、单条修改、toast | ✅ |
| M2 | 批量修改、按应用反查、智能列表 | ✅ |
| M3 | TOML 导入导出 + 差异预览 | ✅ |
| M3 | `⌘Z` 撤销、恢复系统默认 | ⬜ |
| M4 | 异常检测（非常规占用、共享 UTI 提示）、设置窗口 | ⬜ |
| M4 | 图标、空状态、公证、Homebrew cask | 🚧 |

## 8. 开源信息

- 协议：MIT
- 上游参照：[infat](https://tangled.org/did:plc:w45df32pddkw6yywbsrl5r2u/infat)（MIT），更早的 [duti](https://github.com/moretension/duti)
- 与 infat 的关系：独立应用，不依赖其二进制；TOML 格式 100% 兼容，配置可互相搬运。注意 macOS 26 起 infat 的 `set` 已因 legacy API 失效而不可用（详见 [`LAUNCHSERVICES_NOTES.md`](LAUNCHSERVICES_NOTES.md)），所以是「语义对齐，机制升级」
