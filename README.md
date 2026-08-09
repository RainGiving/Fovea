# Fovea

Fovea 是原生 macOS 图片浏览器，围绕快速打开、同目录连续浏览和触控板操作设计。它支持常用图片格式，可在设置中设为默认打开应用。

<p align="center">
  <img src="docs/assets/screenshots/fovea-welcome.png" alt="Fovea 中文欢迎页，提供打开图片和浏览文件夹操作" width="720">
</p>

## 功能

- 支持 JPEG、PNG、GIF、TIFF、BMP、HEIC、HEIF、WebP、AVIF、SVG，以及多种 RAW 和专业图像格式。
- 从 Finder、拖放、最近项目或“打开”菜单载入图片，按自然排序浏览同一目录内容。
- 通过键盘、页边控制和触控板横向滑动切换图片，支持缩放、平移、全屏和连续纵向浏览。
- 提供自动隐藏的胶片栏、信息面板、使用提示、搜索式帮助，以及浅色、深色和跟随系统外观。
- 提供旋转、镜像、自由裁剪、撤销/重做、保存、另存为、重命名、移到废纸篓和在 Finder 中显示。
- 文件夹浏览支持搜索、格式过滤、排序、多选与批量移动、重命名、移到废纸篓，并提供进度、取消和一次性撤销。

## 安装

当前发布包面向 Apple Silicon，要求 macOS 26 或更高版本。

```bash
brew tap RainGiving/tap
brew install --cask fovea
```

更新：

```bash
brew upgrade --cask fovea
```

也可从 [GitHub Releases](https://github.com/RainGiving/Fovea/releases) 下载 `Fovea-X.Y.Z.dmg`，将 `Fovea.app` 拖到“应用程序”。

## 从源码构建

需要 macOS 26 SDK 和 Swift 6.2 或更高版本。

```bash
make check
make build
open .build/Fovea.app
```

常用命令：

```bash
make test      # 运行测试
make audit     # 运行项目审计
make check     # 测试和审计
make dmg       # 生成 .build/artifacts/Fovea-X.Y.Z.dmg
make install   # 安装到 /Applications/Fovea.app
make clean     # 清理 .build
```

`CFBundleShortVersionString` 是发布版本来源，`make version` 会输出当前版本。三个项目使用相同的发布流程：

```bash
make release VERSION=X.Y.Z
git tag vX.Y.Z
git push origin main --follow-tags
```

GitHub Actions 会检查标签与版本号，重新运行检查，生成同名 DMG，并发布到 GitHub Releases。

## 名称迁移

Fovea 是 ImageView 的后续名称。应用包路径为 `/Applications/Fovea.app`，Bundle Identifier 为 `io.github.raingiving.fovea`。安装后可在“设置 → 文件关联”中将 Fovea 设为图片默认打开应用。

`docs/superpowers/`、`docs/qa/` 和历史性能记录保留了 ImageView 名称，用于保存当时的设计和验证上下文。

## 许可

[MIT License](LICENSE)
