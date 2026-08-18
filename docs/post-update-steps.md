# 更新之后必须走的两步

改完代码、测试和审计都通过之后，本地这台机器上还有两件事要做。跳过其中任何一件，
改动都不会体现在日常使用里：`/Applications/Fovea.app` 还是旧版本，或者双击图片
打开的是别的应用。

## 第一步：重新安装到 /Applications

```bash
make install
```

这条命令做了这些事：重新构建 release 版本并打包成 app、结束正在运行的 Fovea、
把 bundle 覆盖到 `/Applications/Fovea.app`、清掉从 iCloud 工作区带过来的扩展属性、
重新签名、用 `lsregister -f` 把新 bundle 注册进 LaunchServices，最后启动它。

不能用 `make build` 代替。那条只产出 `.build/Fovea.app`，`/Applications` 里的那一份不动。

## 第二步：确认图片类型仍然由 Fovea 打开

```bash
make default-app
```

这条命令从 `/Applications/Fovea.app` 的 Info.plist 里读出它声明的全部
`LSItemContentTypes`，逐个把默认打开方式设成 Fovea，然后报出三个数字：
本来就是默认的、这次改过来的、失败的。失败数不为零时命令以非零码退出，
并列出是哪些类型。

为什么每次更新都要跑：重装换掉了 bundle 的签名和 inode，LaunchServices 会把它
当成新的一份记录，原来那些「用 Fovea 打开」的绑定不保证跟过来。常见表现是
JPEG 和 PNG 还正常，但 HEIC、WebP、SVG 或者某几种 RAW 悄悄回到了预览或别的应用。

类型清单不写死在脚本里，直接读应用自己的声明。在 Info.plist 的
`CFBundleDocumentTypes` 里加了新格式之后，这一步不用同步改。

想只对某一份 bundle 生效时给它一个路径：

```bash
swift scripts/set-default-image-app.swift /path/to/Fovea.app
```

## 一次做完

```bash
make check && make install && make default-app
```
