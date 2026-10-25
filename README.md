<p align="center">
  <img src="Assets/Picnic-icon.png" width="160" alt="奶油黄小太阳探出草地绿野餐篮">
</p>
<h1 align="center">Picnic</h1>
<p align="center">把 MacBook 带到阳光下☀️ 🧺</p>
<p align="center">An experimental macOS menu bar app for ambient-light-aware brightness boost.</p>
<p align="center">
  <a href="https://github.com/Guino-Yang/Picnic/releases">下载</a> ·
  <a href="#从源码构建">构建</a> ·
  <a href="docs/TESTING.md">验证范围</a> ·
  <a href="LICENSE">MIT License</a>
</p>

Picnic 是一个轻量的 MacBook 内屏亮度增强工具：在明亮环境中自动选择 **1.5× 或 2×** 增益，平时安静地待在菜单栏。屏幕亮度仍然用键盘亮度键或 macOS 控制中心调节。

这是我的第一个 GitHub 项目，起点很简单：想让 MacBook 在户外更好用一点。

## 它能做什么

- **自动两档增强**：两个滑块分别设定 1.5× 与 2× 的环境光阈值。
- **系统风格的菜单栏图标**：单色线条野餐篮表示待命，实心表示正在增强。
- **平滑切换**：升档等待 3 秒，退档等待 5 秒，档位之间约 2 秒渐变。
- **保留系统亮度控制**：不接管亮度键，不要求在 App 内反复调整亮度。
- **登录自启动**：通过 macOS 原生登录项启用；正常启动默认自动模式。
- **退出即移除增强**：正常关闭或退出时，恢复本程序持有的内屏输出表。
- **只增强内屏**：外接显示器和镜像显示不参与；不联网、不读取屏幕内容。

<p align="center">
  <img src="docs/menu-preview.svg" width="360" alt="Picnic 双滑块菜单示意：自动模式，1500 lx 对应 1.5 倍，3000 lx 对应 2 倍">
  <br><sub>菜单界面示意；实际字体与材质由 macOS 决定。</sub>
</p>

## 自动模式如何工作

| 默认开启阈值 | 档位 | 回落条件 |
| --- | --- | --- |
| ≥ 1500 lx，持续 3 秒 | 1.5× | ≤ 900 lx，持续 5 秒后关闭 |
| ≥ 3000 lx，持续 3 秒 | 2× | ≤ 1800 lx，持续 5 秒后降为 1.5× |

每档的回落线是其开启阈值的 **60%**，因此短暂的阴影不会立刻改变档位。如果直接进入很亮的环境，可直接升至 2×；从很亮变为很暗时，可在 5 秒后直接关闭。

两个滑块采用 **250 lx** 步进，整体范围为 **500–5000 lx**。第二档必须至少比第一档高 250 lx，因此滑块范围会相互约束。这个上限只限制触发阈值，环境光超过 5000 lx 仍可正常触发增强。

**手动模式始终为 2×**，无需环境光传感器；「关闭」立即撤掉增强。

## 适用设备与当前限制

Picnic 面向支持 EDR 的 Apple Silicon MacBook 内屏。构建目标为 macOS 14 及以上；目前实机验证集中在 **14 英寸 M1 Pro MacBook Pro / macOS 27.0.1**，尚未覆盖所有机型、系统版本、显示预设、HDR/DRM 视频及长期户外场景。

**1.5× 和 2× 指显示输出表的增益，不是经过亮度计校准的物理亮度倍数，也不保证固定 1000 nits。** 实际亮度由系统亮度、显示预设、内容、温度和硬件状态共同决定。专业调色时应关闭增强。

自动模式使用动态加载的只读 IOHID 环境光接口，该接口并非公开 API；系统升级可能影响兼容性。App 没有另加过热、低电量、锁屏或休眠暂停策略，macOS 自身的显示休眠和硬件保护仍正常工作。合盖导致内屏离线时无法增强。

## 安装

在 [Releases](https://github.com/Guino-Yang/Picnic/releases) 下载 Apple Silicon 版本，解压后将 `Picnic.app` 放入 `~/Applications` 或「应用程序」，再打开菜单栏野餐篮。

首次公开版本为 **2.0.0**，承接此前的本地迭代。发布构建采用 ad-hoc 签名，**没有 Apple Developer ID 签名或公证**，下载后可能被 macOS 拦截。也可以按下面的步骤在自己的 Mac 上构建；本项目不要求关闭 Gatekeeper、SIP 或 XProtect。

要自动启动，在菜单中勾选「登录时启动」。要卸载，先关闭该登录项、正常退出，再移走 App；没有独立后台守护进程或驱动。

## 从源码构建

需要 macOS 与 Apple 的 Xcode / Command Line Tools（`xcrun`、Swift、clang、macOS SDK）；不需要第三方包管理器或网络依赖。

```sh
git clone https://github.com/Guino-Yang/Picnic.git
cd Picnic
zsh test.sh
zsh build.sh
```

构建脚本会打印本地签名后的 App 路径，并生成 `dist/Picnic.zip`。应用包在临时目录打包，避免云盘给 App 添加元数据后影响签名。图标已包含在仓库中；只有更换原图时才需要运行 `zsh Scripts/build-icon.sh`。

## 实现与验证

Picnic 使用 **256 点 CoreGraphics 显示输出表**调整内屏输出，并通过左上角一个 **1×1 逻辑点的 Metal EDR 触发窗口**维持增强，持续绘制频率为 5 fps。窗口鼠标穿透、不获取键盘焦点；没有整屏白色混合层。

当前硬件上，桌面、菜单和调度中心已进行人工观察；自动 1.5× → 2× → 1.5× → 关闭流程也做过实机检查。纯逻辑和输出表测试目前共 **97 项**。具体覆盖范围与尚未验证的场景见 [测试说明](docs/TESTING.md)。这些检查不能替代亮度计测量或跨设备验证。

| 文件 | 职责 |
| --- | --- |
| `Sources/Policy.swift` | 两档计时、回差与阈值约束 |
| `Sources/AppModel.swift` | 传感器轮询、档位渐变与偏好保存 |
| `Sources/DisplayGain.swift` | 输出表所有权、增益与恢复 |
| `Sources/Overlay.swift` | 小型 EDR 触发窗口与 Metal 绘制 |
| `Sources/AmbientSensor.c` | 只读环境光采样 |
| `Sources/main.swift` | 原生菜单、状态图标和诊断入口 |
| `Sources/LoginItems.swift` | macOS 登录项 |

## 反馈与贡献

欢迎通过 [Issues](https://github.com/Guino-Yang/Picnic/issues) 反馈。描述问题时，请附上 Mac 型号、macOS 版本、显示预设、自动/手动模式，以及是否连接外接屏；无需公开用户名、桌面截图或其他私人信息。

代码与排查过程使用了 Codex 辅助；应用图标由 AI 辅助生成。维护者负责审核、测试与发布。技术参考和保留的第三方许可见 [NOTICES.txt](NOTICES.txt)。

## 许可证

[MIT](LICENSE) © 2026 Guino-Yang。
