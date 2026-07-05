# Deck Video Fixer

一个给 Steam Deck / Linux 用户用的 Proton 视频解码器问题修复小工具。

它的目标不是“压缩视频”或“优化画质”，而是尽量低侵入地修复一些游戏在 Proton/Wine 下播放过场动画时出现的彩条、黑屏、跳过视频、无声等问题。

典型场景包括早期 KOEI TECMO 游戏、旧日系 PC 游戏、旧 galgame、早期 Windows 移植版游戏中常见的 WMV、ASF、MPG/MPEG、旧 AVI、旧 MOV/QuickTime 视频。

---

## 特点

- 不需要除FFMPEG外的任何内容；
- Steam Deck 桌面模式下可直接运行脚本；
- 使用 `ffprobe` 扫描视频信息，使用 `ffmpeg` 转码；
- 默认只处理易出问题格式，不碰正常 MP4/WebM/OGV；
- 转码前备份原文件；
- 保留原路径和原文件名，降低游戏找不到文件的概率；
- 支持从备份还原；
- 支持多种转码策略，由用户在开始前选择；
- 支持FFMPEG下载慢地区：可重试、断点续传、缓存、手动离线放包、自定义镜像 URL；

---

## 适合处理什么问题

适合：

- 游戏过场动画显示成老电视无信号一样的彩条。
- 游戏视频黑屏、跳过、播放失败。
- 游戏目录里能直接看到外置视频文件，例如 `.wmv`、`.asf`、`.mpg`、`.mpeg`、`.avi`、`.mov`。
- Proton / Wine / Steam Deck 下出问题，但 Windows 下正常播放。

不适合：

- 游戏视频打包在 `.cpk`、`.pac`、`.dat` 等资源包里。
- Bink/CRI 等游戏中间件视频，例如 `.bik`、`.bk2`、`.usm`。
- 游戏崩溃、存档、显卡驱动、反作弊、启动器问题。
- 想把所有游戏视频压小或统一转码的通用压片需求。

---

## 默认扫描范围

工具默认关注旧 Windows/旧日系 PC 游戏常见的商业/专有视频格式。

易出问题格式，默认处理：

```text
WMV / ASF / WMA:
.wmv .asf .wm
wmv1 wmv2 wmv3 vc1
wmav1 wmav2 wmapro wmavoice

MPG / MPEG:
.mpg .mpeg .m1v .m2v .vob
mpeg1video mpeg2video
mp1 mp2

旧 AVI / Windows codec:
.avi
msvideo1 msrle msmpeg4v1 msmpeg4v2 msmpeg4v3
cinepak / cvid
indeo2 indeo3 indeo4 indeo5

旧 MOV / QuickTime:
.mov .qt
svq1 svq3 qtrle rpza
```

默认跳过：

```text
.bik .bk2 .smk .usm .cpk .acb .awb .pac
```

现代正常视频默认不处理，例如：

```text
H.264 + AAC 的 MP4
VP8/VP9 + Opus/Vorbis 的 WebM
Theora + Vorbis 的 OGV
```

---

## 文件结构

解压后大概是这样：

```text
deck-video-fixer/
  deck-video-fixer.sh        # 主程序
  get-ffmpeg-for-deck.sh     # 获取静态 ffmpeg/ffprobe 的辅助脚本
  README.md
  LICENSE
```

运行 `get-ffmpeg-for-deck.sh` 后会生成：

```text
bin/
  ffmpeg
  ffprobe

cache/
  ffmpeg-static.tar.xz 或其他已下载的压缩包
```

---

## Steam Deck 上的快速开始

进入桌面模式，解压本工具，然后在工具目录打开 Konsole：

```bash
chmod +x get-ffmpeg-for-deck.sh deck-video-fixer.sh
./get-ffmpeg-for-deck.sh
./deck-video-fixer.sh
```

第一次运行 `get-ffmpeg-for-deck.sh` 会下载 Linux x86_64 静态版 `ffmpeg` 和 `ffprobe`，并放进本工具的 `bin/` 目录。它不会修改 SteamOS 系统分区。

之后运行主工具：

```bash
./deck-video-fixer.sh
```

---

## 获取 ffmpeg / ffprobe

本工具不自带 ffmpeg。推荐使用辅助脚本下载静态版：

```bash
./get-ffmpeg-for-deck.sh
```

测试过的地址是[这个](https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz)，这个地址默认帮你下载最新编译版本。

脚本会优先复用 `cache/` 里的文件，也会尝试从网络下载。它支持 `curl` 或 `wget`，哪个存在就用哪个。

### 下载慢地区的做法

如果默认下载源很慢，可以指定镜像地址：

```bash
FFMPEG_STATIC_URL="https://你的镜像地址/ffmpeg-master-latest-linux64-gpl.tar.xz" ./get-ffmpeg-for-deck.sh
```

如果你已经有代理环境：

```bash
HTTPS_PROXY="http://127.0.0.1:7890" ./get-ffmpeg-for-deck.sh
```

如果 Steam Deck 下载不方便，可以在电脑上下载 Linux x86_64 静态 FFmpeg 压缩包（地址上方有，Github下载链接），然后复制到：

```text
cache/
```

脚本会识别这些常见名字：

```text
cache/ffmpeg-static.tar.xz
cache/ffmpeg-release-amd64-static.tar.xz
cache/ffmpeg-master-latest-linux64-gpl.tar.xz
cache/ffmpeg-master-latest-linux64-lgpl.tar.xz
```

也会尝试识别 `cache/` 下其他 `.tar.xz`，只要压缩包里确实有 `ffmpeg` 和 `ffprobe`。

---

## 如何选择游戏目录

推荐方法：

1. 在 Steam 里选中游戏。
2. 齿轮/右键 → 管理 → 浏览本地文件。
3. Dolphin 文件管理器打开后，复制地址栏路径。
4. 运行工具，把路径粘贴到输入框。

也可以直接把目录传给脚本：

```bash
./deck-video-fixer.sh "/path/to/game"
```

或者：

```bash
PVF_GAME_DIR="/path/to/game" ./deck-video-fixer.sh
```

文件夹选择器模式可以手动指定：

```bash
PVF_PICKER=input ./deck-video-fixer.sh      # 路径输入框
PVF_PICKER=native ./deck-video-fixer.sh     # 系统文件夹选择器
PVF_PICKER=kdialog ./deck-video-fixer.sh    # KDE/kdialog
PVF_PICKER=zenity ./deck-video-fixer.sh     # zenity
PVF_PICKER=terminal ./deck-video-fixer.sh   # 终端输入路径
```

默认模式会先让你粘贴路径；留空后再打开系统文件夹选择器。

---

## 使用流程

1. 运行：

   ```bash
   ./deck-video-fixer.sh
   ```

2. 选择动作：

   ```text
   扫描并转码修复 Proton 兼容性问题视频
   从备份还原
   退出
   ```

3. 选择游戏目录。

4. 查看扫描报告。

5. 选择转码策略。

6. 确认后开始备份并转码。

7. 转码结束后查看日志。

8. 如果全部成功，工具会询问是否删除备份。建议先保留，进游戏确认视频正常后再删。

---

## 转码策略说明

开始转码前会让你选择策略。

```text
recommended    使用扫描推荐
h264_quality   H.264/AAC 高质量，CRF 18
h264_balanced  H.264/AAC 均衡，CRF 22
h264_fast      H.264/AAC 快速，CRF 20 + veryfast
h264_small     H.264/AAC 小体积，CRF 27
h264_baseline  H.264 Baseline，旧解码器兼容
webm_vp9       WebM VP9/Opus 绕过模式
mpeg_mci       MPEG-1/MP2，旧 MPG/MCI 模式
mpeg2_mpg      MPEG-2/MP2，DVD-era MPG 备用
```

### 推荐选择

大多数情况先用：

```text
recommended
```

如果是 WMV/ASF/旧 AVI/旧 MOV：

```text
h264_quality 或 h264_balanced
```

如果是旧日系 PC 游戏的 `.mpg/.mpeg` (不管用时换用h264)：

```text
mpeg_mci
```

如果 H.264 仍然彩条，可以试：

```text
webm_vp9
```

如果空间紧张：

```text
h264_small
```

如果怀疑游戏播放器很老：

```text
h264_baseline
```

也可以用环境变量直接指定策略，跳过选择框：

```bash
PVF_TRANSCODE_MODE=recommended ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=h264_balanced ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=webm_vp9 ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=mpeg_mci ./deck-video-fixer.sh
```

---

## 备份与还原

转码前，原文件会备份到游戏目录下：

```text
.deck-video-fixer-backup/
  files/
  manifest.tsv
  last-run.log
```

例如：

```text
Game/Movie/opening.wmv
```

会备份到：

```text
Game/.deck-video-fixer-backup/files/Movie/opening.wmv
```

还原方法：

```bash
./deck-video-fixer.sh
```

然后选择：

```text
从备份还原
```

工具会把 `.deck-video-fixer-backup/files/` 里的文件复制回原位置。

### 转码后是否删除备份

默认会询问。建议确认游戏内视频正常后再删除。

可用环境变量控制：

```bash
PVF_BACKUP_AFTER_SUCCESS=ask ./deck-video-fixer.sh     # 默认，完成后询问
PVF_BACKUP_AFTER_SUCCESS=keep ./deck-video-fixer.sh    # 总是保留
PVF_BACKUP_AFTER_SUCCESS=delete ./deck-video-fixer.sh  # 全部成功后删除备份
```

如果有任何文件转码失败，工具会自动保留备份。

---

## 常见问题

### 这会不会改坏游戏？

工具会先备份原文件，再替换。只要备份没有删除，就可以还原。

但它仍然会修改游戏目录里的文件。建议一次只处理一个游戏，并先测试开场动画或过场动画是否正常。

### 为什么保留原文件名？

很多游戏只按固定路径找资源，例如 `Movie/opening.wmv`。如果改成 `opening.mp4`，游戏可能找不到。工具会把转码后的文件放回原路径，并保留原文件名。

### 为什么不默认处理 MP4？

正常的 H.264/AAC MP4 在 Proton 下通常不应该转。MP4 出问题时可能是游戏调用 Media Foundation 的方式有问题，而不是格式本身不支持。为了减少误伤，本工具默认只处理旧商业/专有编码格式（特殊编码见下）。

### 为什么不处理 `.bik` / `.bk2` / `.usm`？

这些通常是游戏中间件或专用容器，不是系统 codec 问题。把它们转成 MP4 后改回原扩展名，大概率游戏读不懂。

### 验证游戏完整性后会怎样？

Steam 可能会把被替换的视频还原成原版。如果问题又出现，重新运行工具即可。

### 可以多个游戏一起扫吗？

不建议。最好每次选择一个游戏目录。这样备份、日志和还原都更清楚。

---

## 高级用法速查

```bash
# 直接指定游戏目录
./deck-video-fixer.sh "/path/to/game"

# 指定目录选择方式
PVF_PICKER=input ./deck-video-fixer.sh
PVF_PICKER=terminal ./deck-video-fixer.sh

# 指定转码策略
PVF_TRANSCODE_MODE=h264_quality ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=h264_balanced ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=h264_small ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=webm_vp9 ./deck-video-fixer.sh
PVF_TRANSCODE_MODE=mpeg_mci ./deck-video-fixer.sh

# 指定备份处理方式
PVF_BACKUP_AFTER_SUCCESS=keep ./deck-video-fixer.sh
PVF_BACKUP_AFTER_SUCCESS=delete ./deck-video-fixer.sh

# 使用自定义 ffmpeg 下载源
FFMPEG_STATIC_URL="https://example.com/ffmpeg-master-latest-linux64-gpl.tar.xz" ./get-ffmpeg-for-deck.sh

# 使用代理
HTTPS_PROXY="http://127.0.0.1:7890" ./get-ffmpeg-for-deck.sh
```

---

## 设计原则

这个工具尽量遵守三个原则：

1. **只修易出问题格式**：不做全盘视频优化，不默认改正常视频。
2. **先备份，再替换**：所有转码前先保存原文件。
3. **用户决定策略**：扫描器只给建议，最终转码 preset 由用户选择。

---

## 免责声明

本工具是非官方社区工具。它不会绕过 DRM，不会修改游戏可执行文件，也不会提供任何游戏资源。它只处理用户本地游戏目录中的外置视频文件。

使用前请确认你有权修改自己的本地游戏文件。不同游戏的视频读取方式可能不同，不能保证每个游戏都有效。
