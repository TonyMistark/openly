import Foundation

/// Simplified Chinese table. Key = English source (`t("…")` first argument,
/// `{}` placeholders filled positionally). Adding copy: write
/// `t("English text")` at the call site, then add a line here.
extension Translations {
    static let zh: [String: String] = [
        // MARK: 设置 · 语言

        "Language": "语言",
        "Interface language": "界面语言",
        "Follow System": "跟随系统",
        "Takes effect the next time Openly opens — windows are built at launch.":
            "下次打开 Openly 时生效——窗口文案在启动时构建。",

        // MARK: 设置 · 更新

        "Updates": "更新",
        "Automatically check for updates": "自动检查更新",
        "Checks at most once a day. Nothing is sent from this Mac.":
            "每天最多检查一次，不会从这台 Mac 发送任何数据。",
        "Openly": "Openly",
        "System": "系统",
        "Not checked yet": "还没有检查过",
        "Check for Updates…": "检查更新…",
        "Check Now": "立即检查",
        "Checking…": "正在检查…",
        "Last check failed": "上次检查失败",
        "v{} is up to date": "v{} 已是最新",
        "v{} available": "发现新版本 v{}",
        "Update…": "更新…",
        "Downloading {}%": "下载中 {}%",
        "Installing…": "安装中…",
        "Reveal Download": "显示下载的文件",
        "Release Notes": "发行说明",
        "Download and install v{}, then relaunch": "下载并安装 v{}，装完自动重启",

        // MARK: 设置 · 关于

        "About": "关于",
        "About Openly": "关于 Openly",
        "GitHub Repository": "GitHub 仓库",
        "License": "许可证",
        "MIT License": "MIT 许可证",
        "A macOS utility for managing default apps — see what opens what, change it in bulk, and take your configuration with you.\n":
            "macOS 默认打开方式管理器：一屏看清什么文件用什么打开，批量改、按应用反查、配置可带走。\n",

        // MARK: 更新器 · 失败措辞

        "No app found in the downloaded image.": "下载的镜像里没找到 app。",
        "Could not stage the new app.": "新 app 暂存失败。",
        "The downloaded app is not the promised version.": "下载到的 app 版本和说好的不一样。",
        "Could not replace the installed app.": "替换已安装的 app 失败。",
        "The download could not be mounted.": "下载的镜像挂载失败。",
    ]
}
