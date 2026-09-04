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
- 首次启动自动弹出 Wi‑Fi 名称权限引导并触发系统授权；拒绝后可通过 SystemSettingsKit 精确跳转位置服务设置
- 首次启用时由 macOS 批准一次特权辅助服务，之后切换 IP 与 DNS 不再重复要求密码
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

## 打包为 App

```bash
./Scripts/package-app.sh
```

打包结果位于 `dist/FastNET.app`。脚本会执行 Release 编译、生成 `AppIcon.icns` 并进行本地 ad-hoc 签名。对外分发时仍需使用 Apple Developer ID 签名和公证。

FastNET 使用 `SMAppService` 管理内置 LaunchDaemon，并通过经过调用方校验的 XPC 接口修改网络设置。首次打开时 macOS 会要求管理员批准这个系统级辅助服务；批准后，手动切换与按 SSID 自动切换均不会再次要求密码。对外分发仍需使用 Apple Developer ID 签名和公证。

## 隐私

所有配置只保存在本机 `UserDefaults` 中。FastNET 不联网，也不会收集或上传网络信息。

macOS 14 及更高版本要求应用取得位置服务授权后，CoreWLAN 才会返回当前 Wi‑Fi 名称。FastNET 只使用该权限读取 SSID，不请求定位坐标。权限设置跳转使用 [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow) 中的 `SystemSettingsKit`。
