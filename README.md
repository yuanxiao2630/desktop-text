# 桌面文字 · Desktop Text

一个轻量的 macOS 菜单栏工具。把提醒、警示语或当天安排放在桌面，调整字体和位置后锁定；锁定后的文字不会接收鼠标点击，也不会抢输入焦点。

## 功能

- 多段文字，分别保存内容、位置和样式。
- 解锁后直接在桌面输入；拖动上方小条定位，拖动右下角调整文字框。
- 选择本机字体、字号、颜色、粗体、斜体、下划线、阴影、对齐、行距和不透明度。
- 透明背景或带底色的便签。
- 桌面显示与始终置顶两种模式。
- 一键锁定与鼠标穿透；从菜单栏解锁。
- 自动保存、删除恢复，以及可选的登录时启动。

使用 Swift 和 AppKit 编写，不需要第三方依赖。文字数据保存在本机，不包含云同步或遥测。

## 下载与使用

从 [Releases](https://github.com/mango2630/desktop-text/releases) 下载应用压缩包。解压后打开「桌面文字.app」，也可将应用拖到「应用程序」文件夹。

要求 macOS 14 或更高版本。首个下载版本为 Apple 芯片版；Intel Mac 可在对应机器上从源码构建，也可以构建通用版本。

1. 在管理窗口输入文字，并选择字体、字号与样式。如果文字已经锁定，先点击「解锁并编辑」。
2. 收起编辑窗口，切回桌面，拖动文字上方的小条定位。
3. 点击小锁，或在桌面编辑文字时按 Esc，即可锁定。
4. 再次修改时，点击顶部菜单栏「桌面文字」→「管理与编辑…」→「解锁并编辑」。

「贴在桌面」会被普通应用窗口盖住；「始终置顶」在锁定后显示于普通窗口上方。关闭管理窗口后，应用仍在菜单栏运行；完全退出请使用菜单栏中的「退出桌面文字」。

完整说明见 [使用说明](docs/使用说明.txt)。

### 关于应用签名

当前下载版本使用本机构建签名，尚未使用 Apple Developer ID 签名或经过 Apple 公证。其他 Mac 从网络下载后可能被系统拦截；可以从源码在自己的 Mac 上构建。公开仓库和下载版本不代表应用已经通过 Apple 审核。

## 从源码构建

需要 macOS 14+、Python 3 和支持 macOS 14 的 Xcode 命令行工具。无需付费开发者会员。

```sh
git clone https://github.com/mango2630/desktop-text.git
cd desktop-text
python3 scripts/build.py
```

输出文件：

```text
dist/桌面文字.app
dist/桌面文字.zip
```

构建脚本默认使用当前 Mac 的架构，也可指定目标：

```sh
python3 scripts/build.py --arch arm64
python3 scripts/build.py --arch x86_64
python3 scripts/build.py --arch universal
```

`--output` 可以指定其他输出目录。也可使用 `make build`、`make universal`、`make run`。

## 验证

```sh
make test
```

原生检查覆盖内容和样式保存、重启恢复、锁定后的鼠标穿透、键盘焦点、显示层级，以及删除恢复。部分检查会短暂创建测试窗口，需要有图形桌面会话；请在本机执行。

GitHub Actions 自动检查源码构建与应用签名完整性，并保存构建产物。

## 文件结构

```text
src/main.swift          应用、桌面窗口、编辑界面与原生检查
src/icon.swift          应用图标绘制
scripts/build.py        构建、打包和本机签名
docs/使用说明.txt       操作说明
dist/                   生成的应用和压缩包，不进入 Git 历史
.build/                 临时构建文件，不进入 Git 历史
```

个人文字、位置和样式保存在 `~/Library/Application Support/DesktopText/notes.json`，与源码目录分开。移动或更新应用文件会继续使用已经保存的数据。
