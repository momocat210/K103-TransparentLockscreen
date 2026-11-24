# K103 透明随机锁屏（v1.6）

> 把海信 A5 Pro 的「随机透明锁屏」移植到 **Boyue Likebook K103** 墨水屏阅读器的 Magisk 模块 —— 熄屏时用随机贴纸 + 锁屏前最后一帧合成待机图，每次锁屏画面不同且透出真实内容。

## 适配设备

| 项 | 要求 |
|---|---|
| 设备 | Boyue Likebook K103 |
| 系统 | Android 8.1 / arm64 |
| Root | 已 root 且安装 Magisk（无需 Xposed） |
| 不改 | EPD 波形 / HWC / SystemUI / boot 均不修改，只写 `standby.jpg` + `temp.jpg` |

## 功能

- **随机换图（默认）**：洗牌队列，一轮内每张壁纸恰好出现一次，跨轮避重，杜绝高频重复；图库增删自动重洗。
- **透明锁屏**：亮屏期间预合成，透出「锁屏前最后一帧」；固定贴纸、纯白底两种模式可切。
- **控制端 APP**：圆角界面「猫猫透明锁屏 forAlita」，可切换随机/固定、缩放（fit/cover/stretch）、画质、抓帧频率（0.5/1/2s）、立即换图、还原原厂图等。
- **eMMC 保护**：`framecmp_k103` 在内存中比较帧，画面没变化就不写 10MB 图像。
- **无损升级**：升级安装保留 `settings.conf` 与 `backup`，不丢配置与原厂图；卸载自动还原原厂锁屏图。

## v1.6 修复了什么

1. **连续同一画面锁屏总是同一张壁纸** —— 反编译 HWC 发现 `sys.by.standbysetting=1` 时会跳过自定义图改画原厂默认图；v1.6 改为不再发广播 + 熄屏前把属性归零。
2. **透出部分不是锁屏前画面** —— 旧版熄屏后 2~3 秒才写图，HWC 早已读完；v1.6 改为亮屏期间「预合成」，画面一变就原子替换 `standby.jpg`。
3. **新增 `framecmp_k103`** —— 抓帧只在内存比较，减少无谓的闪存写入。

完整机制、反编译证据与实机验证记录见 [移植说明.md](移植说明.md)。

## 安装

1. 面具（Magisk）→ 模块 → 从本地安装 → 选择 `1-模块安装包/K103-TransparentLockscreen-v1.6.zip` → 重启。
2. 把至少 1 张 PNG/JPG 放入 `/sdcard/Pictures/K103_Lockscreen/`（建议 2 张以上，支持一层子目录；旧目录 `A5Pro_Lockscreen` 自动迁移）。**包内不含任何图片素材。**
3. 安装控制端：文件管理器点击 `1-模块安装包/猫猫透明锁屏forAlita-v1.2.apk`，首次打开授权 root。
4. 之后每次按电源键熄屏即随机换图并透出锁屏前画面。

也可直接下载 [GitHub Release](../../releases/tag/v1.6) 里的安装包。

## 命令行

```sh
sh /data/adb/modules/k103_transparent_lockscreen/tools/lockscreen_ctl.sh status
... next | enable 0/1 | reset | mkdir | gallery | log | restore
... set SCALE cover | set SHUFFLE 0 | set JPEG_QUALITY 95
... set BG_MODE white | set TRACK_EVERY 2
... set BROADCAST 1 | set PRECOMPOSE 0 | set FORCE_STANDBYSETTING 0
```

## 目录

| 路径 | 说明 |
|---|---|
| `1-模块安装包/` | 可直接安装的 Magisk 模块 zip 与控制端 APK |
| `2-源码/build_zip.py` / `build_app.py` / `package_all.py` | 模块打包 / APP 回编译签名 / 完整包生成脚本 |
| `2-源码/module/` | Magisk 模块源文件：守护脚本、控制工具、配置、脚本与 arm64 二进制工具 |
| `2-源码/native/` | C 源码 + stb 单头文件库（`img2raw` / `compose` / `framecmp`） |
| `2-源码/app/` | 控制端 APP 源码（AndroidManifest / assets/index.html / smali） |
| `移植说明.md` | 机制说明、各版本改动、反编译证据与实机验证 |
| `README-先看我.txt` | 原始交付说明 |

## 重新构建

依赖：apktool、uber-apk-signer、jdk4py(JRE)、Python（路径见 `build_app.py`）。

```sh
# native 工具（arm64）
zig cc -target aarch64-linux-musl -static -O2 2-源码/native/img2raw_k103.c -o 2-源码/module/img2raw_k103
zig cc -target aarch64-linux-musl -static -O2 2-源码/native/compose_k103.c  -o 2-源码/module/compose_k103
<NDK>/toolchains/llvm/prebuilt/*/bin/clang --target=aarch64-linux-android21 -O2 \
  2-源码/native/framecmp_k103.c -o 2-源码/module/framecmp_k103

python 2-源码/build_zip.py     # 重打 Magisk 模块
python 2-源码/build_app.py     # 重编并签名控制端 APP
python 2-源码/package_all.py   # 生成完整分发包
```

## 来源与许可

- 本项目由 **momo_cat** 基于海信 A5 Pro「随机透明锁屏」模块，按 K103 墨水屏环境重新实现，属独立移植作品。
- `native/` 使用 [stb_image](https://github.com/nothings/stb) / stb_image_write 单头文件库（公共领域 / MIT）。
- 控制端 APP 沿用 WebView + smali root 桥方案。
- 包内二进制工具由上述 C 源码编译而来，源码一并公开。

— momo_cat
