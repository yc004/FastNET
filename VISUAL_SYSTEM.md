# FastNET 视觉系统

FastNET 采用原生 macOS 菜单栏工具的视觉语言：系统字体、SF Symbols、系统材质和强调色。界面不使用自绘按钮或复杂装饰，以保持轻量并自然适配浅色、深色和提高对比度模式。

## 主应用图标

- **Wi‑Fi 波纹**：代表当前无线网络。
- **双向箭头**：代表在不同网络配置之间自动切换。
- **深蓝与青色**：表达网络连接、稳定和系统工具属性。
- **白色主符号**：确保在小尺寸下仍有清晰轮廓。
- **全出血底图**：AppIcon 源图不预先绘制透明圆角、边框或外部阴影，由 macOS 统一施加系统圆角蒙版，避免 Finder 再添加旧式图标底板。

资源：

- `Sources/FastNET/Resources/FastNET-AppIcon-Master.png`：1254 × 1254 原始图。
- `Sources/FastNET/Resources/AppIcon.iconset/`：16、32、128、256、512 和 Retina 尺寸。

## 菜单栏图标

菜单栏严格使用单色 SF Symbols，不使用彩色主图标。展开内容使用系统原生 `NSMenu` 风格，而不是自定义浮层：

| 状态 | SF Symbol |
| --- | --- |
| 已连接 | `wifi` |
| 未连接 | `wifi.slash` |

系统会自动处理菜单栏的浅色、深色、选中和高对比度状态。

原生菜单只承载当前网络、立即应用、自动切换、刷新和管理入口；IP/DNS 编辑等复杂任务放入独立原生窗口，避免在菜单栏中模拟表单。

## 功能图标

| 语义 | SF Symbol |
| --- | --- |
| Wi‑Fi 配置 | `wifi.circle.fill` |
| 自动 DHCP | `bolt.fill` |
| 手动 IPv4 | `number.square` |
| DNS | `globe` |
| 配置管理 | `slider.horizontal.3` |
| 应用成功 | `checkmark.circle.fill` |
| 警告 | `exclamationmark.triangle.fill` |
| 更多操作 | `ellipsis.circle` |

所有符号名称集中定义在 `Iconography.swift`，避免后续页面使用不一致的图标。

## 使用规则

- 菜单栏图标保持单色，不放文字或徽标。
- 主图标只用于应用身份、关于页和弹窗顶部，不替代状态图标。
- 绿色只表示已连接或应用成功；红色只表示配置错误。
- 网络状态不可只依靠颜色表达，应同时使用符号或文字。
