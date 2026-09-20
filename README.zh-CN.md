# Keyboard Hajimi Groove

简体中文 | [English](README.md)

Keyboard Hajimi Groove 是一个 macOS 菜单栏应用，为常用工作快捷键播放由用户自行准备的本地音乐片段。它面向希望给复制、粘贴、撤销、保存、查找和功能键等操作加入即时声音反馈的人；普通文字输入不会触发音频。

> 当前仓库发布的是源码，不包含音轨、已签名的 `.app` 或 `.dmg` 安装包，也不提供自动更新。克隆仓库后可以构建应用并验证快捷键逻辑；要听到声音，还需要提供自己有权使用的音频文件。

## 它会做什么

- `Command+C`、`Command+V`、`Command+Z`、`Command+S`、`Command+F` 等工作流快捷键可以触发短音乐片段。
- `F1`–`F12` 可以触发功能键反馈。
- 音频只从本地文件读取；仓库不会下载或上传音频。
- 菜单栏中的 `哈` 提供重新加载主题、打开切片编辑器、打印和重置本地按键分析等操作。

## 源码构建与应用下载

本仓库目前没有可直接下载并双击安装的官方签名应用。GitHub 仓库中的源码压缩包也不是已经构建好的 macOS 应用。

要使用当前版本，请从源码运行：

```sh
git clone https://github.com/hellowmq/keyboard-hajimi-groove.git
cd keyboard-hajimi-groove
make doctor
swift run keyboard-hajimi-groove
```

`make doctor` 会检查 Swift、`ffmpeg`、`afinfo` 和两份 JSON 配置，并运行 `swift test`。它不会替你提供音频素材。应用默认读取 `Themes/shortcut-local-drops.json`，启动后在 macOS 菜单栏显示 `哈`。

首次启动时，macOS 可能要求你为启动进程的终端授予“辅助功能”或“输入监控”权限。没有本地音频时应用仍可启动，但触发快捷键只会打印缺少采样文件的提示。

## 前置条件

- macOS 14 或更高版本
- Swift 6.3 或更高版本
- Python 3，用于本地音频切片和编辑工具
- `ffmpeg`，用于生成本地音频片段
- macOS 自带的 `afinfo`，用于素材验证

## 权限与隐私

应用通过 macOS 的只监听事件 tap 观察全局按键和修饰键，再仅对配置中的快捷键进行匹配、播放和本地汇总分析。它不拦截、不注入，也不改写输入。

请只在自己控制的 Mac 上授予“辅助功能”或“输入监控”权限。使用结束后可以退出应用，并在“系统设置 → 隐私与安全性”中撤销对应终端或宿主应用的权限。

切片编辑器默认只监听 `127.0.0.1`。不要把它暴露到公共网络。安全问题的私下报告方式见 [SECURITY.md](SECURITY.md)。

## 准备有权使用的音频

请只使用你创作、已获授权，或依法有权处理的音频。本仓库的 MIT 许可证只覆盖代码，不授予任何第三方音频的使用权。

原始 WAV 文件放在：

```text
Samples/hajimi-local/raw/
```

生成的 M4A 片段写入：

```text
Samples/hajimi-local/clips/
```

这两个目录默认被 Git 忽略。切片计划位于 `Samples/hajimi-local/segment-plan.json`；其中的源文件名必须与你提供的文件一致，也可以按自己的素材修改。完整边界见 [docs/ASSETS.md](docs/ASSETS.md)。

## 切片工作流

查看切片计划：

```sh
make list-hajimi-segments
```

重新生成一个片段或全部片段：

```sh
make recut-hajimi-one ID=drop-copy
make recut-hajimi
```

启动本地网页编辑器：

```sh
make segment-ui
```

编辑器默认打开 `http://127.0.0.1:8765`，可预览区间并调整 `start`、`duration`、`fadeIn`、`fadeOut` 和 `volume`。切片原则见 [docs/SEGMENTATION.md](docs/SEGMENTATION.md)。

## 如何理解验证结果

```sh
make validate-code
```

该命令验证两份 JSON 并运行 Swift 测试，说明配置可解析、已覆盖的快捷键处理逻辑符合测试预期；它不证明全局权限已经授予，也不证明本地音频存在或能正常播放。

只有准备好原始文件和生成片段后，才运行：

```sh
make validate-assets
make validate-hajimi
```

`validate-assets` 会检查预期目录中是否有 WAV/M4A 文件，并用 `afinfo` 验证片段。`validate-hajimi` 同时执行代码与素材检查。它们仍不能替代在实际 Mac 上试听每个片段和检查音量、节奏、淡入淡出。

## 已知限制

- 当前没有官方签名安装包，使用者需要本地 Swift 工具链。
- 音频不会随源码提供；缺少音频时只能验证启动和逻辑，无法获得可听反馈。
- 全局快捷键监听依赖 macOS 权限，权限对象通常是启动它的 Terminal、iTerm 或其他宿主应用。
- 菜单栏反馈来自预先配置的快捷键匹配，不分析普通输入文本的语义。
- 切片编辑器是本地开发工具，不应作为公网服务部署。

## 开发

```sh
swift test
make validate-code
```

## 许可证

代码使用 [MIT License](LICENSE)。音频素材不包含在仓库中，其权利和许可由素材本身决定。
