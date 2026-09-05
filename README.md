# FastNET

FastNET 是一个轻量的 macOS 菜单栏网络配置切换工具。它按 Wi‑Fi 名称（SSID）保存 IPv4 与 DNS 配置，并在网络变化时自动应用对应配置。

## 功能

- 为每个 Wi‑Fi 保存独立的 DHCP 或静态 IPv4 配置
- 为每个 Wi‑Fi 保存独立 DNS 服务器
- 可选择在手动 DNS 后附加路由器通过 DHCP 提供的默认 DNS，并自动去重
- 一个 SSID 可保存多个带备注的配置，并从菜单中手动切换
- 每个 SSID 最多指定一个连接后自动应用的配置
- 可从当前网络、系统已保存网络和已有配置中选择目标 SSID，也支持手动输入
- 检测 Wi‑Fi 变化并自动切换
- 首次启动以双步骤状态卡检查 Wi‑Fi 名称权限和安装器部署的系统帮助程序；通过 PermissionFlow 的 SystemSettingsKit 精确跳转位置服务
- PKG 安装时由 macOS 原生安装器完成一次管理员授权，之后切换 IP 与 DNS 不再重复要求密码
- 在权限未授予时会于后续启动继续显示引导，不会因关闭过窗口而永久跳过
- 菜单栏快速查看当前 IP、配置并手动应用
- 配置窗口顶部直观显示当前 SSID、IPv4、子网掩码、路由器、DNS、网络服务和配置方式
- 使用类似“备忘录”的原生三栏布局：网络名称、配置文件、配置详细信息
- 配置文件栏实时标识“正在应用”“当前应用”和“应用失败”状态
- 自动切换时从菜单栏图标弹出原生 Liquid Glass 消息气泡，提示进度、成功或失败状态
- 使用系统原生菜单栏菜单，支持标准高亮、键盘操作和自动明暗模式
- 使用克制的原生状态动效，并自动遵循系统“减少动态效果”设置
- 默认在 Dock 中显示应用图标，可从菜单栏随时隐藏或恢复
- 启动时检查并唤醒已授权的帮助程序，退出 FastNET 时同步停止帮助程序进程
- 原生 SwiftUI 界面，不依赖第三方运行时
- 完整 macOS 应用图标尺寸与统一 SF Symbols 视觉规范

## 运行

需要 macOS 26 或更高版本，以及完整安装的新版 Xcode。开发时可用 Xcode 打开 `Package.swift`。涉及实际网络配置切换时，请运行打包后的 `.app`，因为免密码辅助服务必须位于应用包中。

```bash
swift run FastNET
```

## 打包安装器

```bash
./Scripts/package-app.sh
./Scripts/package-installer.sh
./Scripts/package-dmg.sh
```

打包结果位于 `dist/FastNET.app`、`dist/Install-FastNET-<版本>.pkg` 和 `dist/FastNET-<版本>-macOS.dmg`。用户双击 DMG 中的安装包并完成一次原生管理员授权后，安装器会同时安装 FastNET、特权帮助程序及 LaunchDaemon。以后切换 IP 和 DNS 不再重复要求密码。

正式构建需要 Apple Developer ID Application 证书和 notarytool 钥匙串配置：

```shell
FASTNET_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
FASTNET_INSTALLER_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
FASTNET_NOTARY_PROFILE="FastNET" \
./Scripts/package-dmg.sh
```

脚本会依次签名主应用、帮助程序、PKG 和 DMG，启用 Hardened Runtime，提交 Apple 公证并装订公证票据。未设置证书时会生成仅供本机测试的 ad-hoc 应用与未签名 PKG。

FastNET 通过一次性 PKG 将最小化的 LaunchDaemon 安装到系统目录，并使用经过调用方身份校验的 XPC 接口修改网络设置。帮助程序只接受预定义的网络配置请求，不执行任意命令。公开分发时仍应使用 Developer ID 签名并完成公证。

## 隐私

所有配置只保存在本机 `UserDefaults` 中。FastNET 不联网，也不会收集或上传网络信息。

macOS 14 及更高版本要求应用取得位置服务授权后，CoreWLAN 才会返回当前 Wi‑Fi 名称。FastNET 只使用该权限读取 SSID，不请求定位坐标。权限设置跳转使用 [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow) 中的 `SystemSettingsKit`。
