# PhotoFilter

简体中文 · **[English](README.md)**

免费、开源、键盘优先的 macOS 照片清理工具。所有分析都在本机完成——你的照片永远不会离开你的 Mac。

![CI](https://github.com/hsuBnOediH/photo-filter/actions/workflows/ci.yml/badge.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

PhotoFilter 直接操作**系统照片图库**（也就是 iCloud 同步的那个），删除会进入「最近删除」（30 天内可恢复）并同步到 iPhone。这是它和文件夹式去重工具的本质区别：不用导出、不会硬删、不搞第二套图库。

## 模块

| | |
|---|---|
| 📸 **截图清理** | 刷卡式审阅：`←` 删除、`→` 保留、`↑` 撤销，几分钟清掉几百张过期截图。进度自动保存——随时退出，下次接着刷。 |
| 🖼 **个人照片** | 找出相似照片组（同时间同地点 + 本地视觉模型确认同场景），自动推荐每组最该留的一张，**一次只审一组**。扫描边跑边出结果，随时可停——一切都有缓存、可续传。 |
| 👥 **共享相册** | 浏览 iCloud 共享相册，批量移除你自己发布的内容。 |
| 🎬 **视频** | 敬请期待。 |

## 亮点

- **键盘优先、全键位可自定义** —— 每个按键都能在设置（⌘,）里改绑；随时按 `?` 查看实时快捷键表。
- **放大态全功能审阅** —— 放大状态下所有审阅键照常工作；按 `Enter` 不离开全屏直接跳下一组，`Z` 像素级平移，`C` 与推荐保留照并排对比。
- **流式扫描** —— 扫描开始几秒后相似组就开始出现（最新的在前），边扫边审边删。
- **处处可续传** —— 扫描结果、标记、审阅进度都能跨启动恢复；照片特征指纹落盘缓存，重扫近乎瞬时。
- **中英双语** —— 跟随系统语言。
- **安全设计** —— 在你确认系统删除弹窗之前，图库不会有任何改动；删除进入「最近删除」（30 天可恢复）。如果你启用了 iCloud 共享图库，App 会提醒你删除对所有成员生效。

## 隐私

- 所有分析（Apple Vision 特征向量）都**在本机运行**，任何照片、缩略图、元数据都不会上传。
- 无统计、无遥测、无第三方 SDK。
- App 唯一可能发出的网络请求是向 GitHub Releases API 查询新版本（可在设置中关闭）。
- 不信？代码全在这个仓库里——两条命令自己编译。

## 安装

1. 从 [Releases](https://github.com/hsuBnOediH/photo-filter/releases) 下载最新的 `PhotoFilter-x.y.z.dmg`。
2. 把 **PhotoFilter** 拖进「应用程序」。
3. 首次打开时 macOS 会提示开发者身份无法验证（应用暂未公证）。任选其一放行：
   - 右键 App → **打开** → **打开**；或
   - 系统设置 → 隐私与安全性 → 拉到底部 → **仍要打开**；或
   - 终端执行 `xattr -cr /Applications/PhotoFilter.app`。
4. 按提示授予照片**完全访问**权限（必须——App 的全部功能就是读取和删除照片）。

要求 macOS 14 (Sonoma) 或更新；通用二进制（Apple Silicon + Intel 都支持）。

## 从源码构建

不需要 Xcode，只要命令行工具：

```bash
git clone https://github.com/hsuBnOediH/photo-filter.git
cd photo-filter
./build-app.sh            # 本机架构；加 --universal 出双架构
open PhotoFilter.app      # 用 Finder/open 启动，不要用 `swift run`
                          #（照片权限绑定在 App bundle 上，不是终端上）
```

## 参与贡献

欢迎 Issue 和 PR——见 [CONTRIBUTING.md](CONTRIBUTING.md)。适合上手的方向：新语言、视频模块、更聪明的保留推荐算法。

## 许可证

[MIT](LICENSE)
