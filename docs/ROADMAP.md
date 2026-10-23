# 路线图

按里程碑拆解。状态标记：✅ 完成 / 🚧 部分完成 / ⬜ 未开始

---

## M0 · LaunchServicesKit（✅ 完成）

可复用的 Swift Package，GUI 与 CLI 共用。

- [x] `LSKAssociation.info(forExtension:)` / `(forURLScheme:)` / `(forType:)` 查询
- [x] `LSKAssociation.setDefaultApp(_:forExtension:)` / `(forURLScheme:)` / `(forType:)`
- [x] `.html` → `http` scheme 的特例路由
- [x] `https` 与 `http` 共享 handler 的处理
- [x] `public.html` / `com.apple.default-app.web-browser` → `http` 路由
- [x] `LSKDatabase.handlers()` 解析 secure plist
- [x] `LSKAppResolver`：名称 / 路径 / bundleID 三向解析
- [x] `LSKSupertypes`：24 种回退类型表
- [x] `TOMLConfig` 编解码（infat 三张表，含转义）
- [x] `lsk` 命令行验证工具
- [x] 27 项单元测试（查询 8 / 数据库 6 / 回退类型 7 / TOML 6）

验收方式：`lsk info --ext x` 与 `infat info --ext x` 输出一致（查询侧仍成立）。

## M1 · 可用 Alpha（✅ 完成）

- [x] `NavigationSplitView` 三栏骨架
- [x] 关联总览列表（plist ∪ 常用扩展名，三层兜底）
- [x] 侧栏智能列表 + 文件类别（基于 UTType 继承推导）
- [x] 工具栏搜索（扩展名 / UTI / 默认应用名）
- [x] 行内默认应用图标 + 无默认红色徽标 + 悬浮显示路径
- [x] 单条修改 popover + 注册应用单选
- [x] 「浏览其他应用…」（NSOpenPanel + LSRegisterURL）
- [x] toast 反馈
- [x] ↑↓ 键盘导航 + ↩ 打开选择器

## M2 · 功能完整 Beta（✅ 完成）

- [x] 批量勾选（含全选当前视图）+ 底部批量条
- [x] 批量 sheet（候选 = 目标行注册应用并集）
- [x] 逐条执行 + 跳过 / 失败分类汇总
- [x] 按应用视图：应用排行侧栏 + 接管清单 + 全部转移给…
- [x] 智能列表「无默认应用」
- [x] 智能列表「最近修改」+ UserDefaults 持久化（上限 50）

## M3 · 候选发布版（🚧 部分完成）

- [x] 导出 TOML（infat 兼容三张表）
- [x] 导出 sheet：预览 + 拷贝 + 存盘
- [x] 导入 TOML + 差异计算（新增 / 覆盖 / 一致）
- [x] 差异 sheet + 确认后按应用分组执行
- [ ] `⌘Z` 撤销（需要 undo 栈，目前 recentChanges 只是日志）
- [ ] 「恢复系统默认」（清掉该类型的用户设置，交还系统）

## M4 · 1.0 打磨（🚧 部分完成）

- [x] 应用图标（icns + iconset）
- [x] `make-app.sh` / `make-dmg.sh` 打包脚本
- [x] 空状态视图
- [x] 设置窗口（语言 / 更新 / 关于，借鉴 wtmd 的单页 Form 布局）
- [x] 检查更新：GitHub Releases API + 24h 节流 + 启动自动检查（可关）
- [x] 一键更新：下载（分块落盘带进度）→ 挂载 dmg → 暂存校验版本 → 换原子换装 → 脱壳重启；失败退回 Finder
- [x] 中英双语文案：`t()` 翻译层 + 代码内中文表（英文原文即键），设置页与更新链路全覆盖
- [ ] 设置窗口里的 GUI 修改同步写回 `~/.config/infat/config.toml`
- [ ] 异常检测：「非常规占用」（.html 非浏览器、.pdf 被脚本工具接管等）
- [ ] 异常检测：「共享 UTI 联动提示」（yml / yaml 等成组类型行内 ⚠）
- [ ] Developer ID 签名 + 公证
- [ ] Homebrew cask
- [ ] README 截图与动图

---

## 下一步优先级

1. **`⌘Z` 撤销 + 恢复系统默认** —— 补上「零危险操作」这条产品原则的最后一块。这两个功能共享同一个基础设施：每次 set 之前把旧值压栈
2. **异常检测两项** —— 这是 Openly 相对系统设置最有说服力的差异点，也是 infat 用户迁过来的理由
3. **签名与分发** —— 没有公证，陌生人拿到 DMG 会卡在 Gatekeeper，等于没法分享

## 已知问题

- `import` 之后用固定延时（`count × 1.5s + 1s`）触发全量重载来等待系统确认框逐项完成——这是在等用户点确认框，不确定性高。更好的做法是监听 Launch Services plist 的修改时间，或在批量结束后提供手动刷新入口
- 搜索不覆盖「注册应用名」和「bundle ID」，尽管搜索框提示文案写了「或应用」
- 批量 sheet 的候选只取目标行注册应用的并集，没在集合里的应用需要先单独设置一次
