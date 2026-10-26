# 星环竞技场

Windows / Android 离线2D自动对战游戏。支持2～8人个人竞技与组队、角色编辑、多状态PNG形象、技能数值调整和完整对局记录；安卓采用竖屏布局，每次开局自动更换随机种子。

已内置：毁灭·星、花火、云璃、阿格莱雅、绯英、记忆·星、遐蝶、黄泉。

## 参考来源

本游戏的玩法与战斗演出参考了这位B站UP主的视频制作：[UP主B站主页](https://space.bilibili.com/282618110)。感谢原作者的创意与演示。本项目为独立制作的非官方同人游戏。

角色素材及音乐的权利归各自权利人，详见[第三方素材说明](THIRD_PARTY_NOTICES.md)。

## 下载

- [安卓APK（竖屏）](https://github.com/Sobossy/StarRingArena/releases/latest/download/StarRingArena.apk)
- [Windows运行包](https://github.com/Sobossy/StarRingArena/releases/latest/download/StarRingArena-Windows.zip)：完整解压后运行 `Windows/SpiritArena.exe`，保留同目录的PCK文件。
- [源码包](https://github.com/Sobossy/StarRingArena/releases/latest/download/StarRingArena-Source.zip)
- [更新记录](https://github.com/Sobossy/StarRingArena/releases)

安卓使用相同包名与签名覆盖安装，可保留数据。电脑与手机存档各自保存，暂不自动同步。

## 使用与开发

选择角色、人数、地图和队伍后开始自动对战。支持暂停、0.5／1／2倍速及音乐开关、音量控制；正常结束后保存战报，中途中断不记录。

- **源码启动：** 双击 `StartGame.cmd`；缺少工具时自动配置Godot 4.7.2。
- **开发与打包：** `OpenEditor.cmd` 打开工程，`BuildGame.cmd` 导出Windows，`BuildAndroid.ps1` 导出APK；`UpdatePhone.cmd` 可覆盖安装到已授权的USB调试手机。
- **快捷键：** Space暂停，R重新开局，F11切换全屏。
- **存档：** Windows位于 `%APPDATA%/StarRingArena/`，包含角色、设置与对局记录。更新时保留该目录。

详细说明：[角色编辑与多人配置](docs/角色编辑与多人对战.md) · [对局记录](docs/对局记录.md) · [安卓使用](docs/安卓使用说明.md) · [角色与技能扩展](docs/角色与技能扩展.md)
