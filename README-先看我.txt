================================================================
 Boyue Likebook K103 透明随机锁屏 —— 源码 + 安装包（v1.6）
================================================================

【1-模块安装包】直接用于设备安装
  K103-TransparentLockscreen-v1.6.zip
      Magisk 模块（标准结构）：面具 → 模块 → 从本地安装 → 重启。
      图库放 /sdcard/Pictures/K103_Lockscreen/，熄屏即随机换图并透出锁屏前画面。
      升级安装会保留原 settings.conf 与 backup，不会丢配置/原厂图。
  猫猫透明锁屏forAlita-v1.2.apk
      圆角控制端 APP：文件管理器点击安装，首次打开授权 root。
      可切换随机/固定、缩放、画质、抓帧频率(0.5/1/2s)、立即换图、还原原厂图等。

【v1.6 修复了什么】
  1. 连续同一画面锁屏总是同一张壁纸：
     反编译 hwcomposer 发现，熄屏绘制时若系统属性 sys.by.standbysetting=1
     （Settings 正在设置壁纸），HWC 会跳过自定义图、直接画原厂默认图。
     旧版熄屏后发广播恰好会触发这个状态。v1.6 改为不再广播 + 熄屏前把属性归零。
  2. 透出部分不是锁屏前画面：
     旧版熄屏后 2~3 秒才写图，而 HWC 熄屏瞬间就已读完文件。
     v1.6 改为亮屏期间“预合成”：画面一变就合成并原子替换 standby.jpg，
     熄屏时 HWC 读到的就是最后一帧；熄屏时再准备下一张贴纸，保证连续锁屏也轮换。
  3. 新增 framecmp_k103：抓帧只在内存比较，画面没变就不写 10MB，保护 eMMC。

【2-源码】可修改后自行重新构建
  build_zip.py   重新打包 Magisk 模块 zip（标准结构，根目录放 module.prop）
  build_app.py   重新构建并签名控制端 APP（apktool 回编译 assets/index.html / smali）
  package_all.py 生成这个完整分发包
  native/        C 源码 + stb 单头文件库
                 img2raw_k103 / compose_k103（arm64 静态）
                 framecmp_k103（arm64 动态，NDK clang 编译）
  module/        Magisk 模块源文件：service.sh 守护、tools/lockscreen_ctl.sh 控制端、
                 配置文件、脚本，以及二进制工具和白底模板 frame_white.raw
  app/           控制端 APP 源码：AndroidManifest / assets/index.html(界面) / smali

  重新编译 native：
    zig cc -target aarch64-linux-musl -static -O2 native/img2raw_k103.c -o module/img2raw_k103
    zig cc -target aarch64-linux-musl -static -O2 native/compose_k103.c  -o module/compose_k103
    <NDK>/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe \
      --target=aarch64-linux-android21 -O2 native/framecmp_k103.c -o module/framecmp_k103

【文档】
  移植说明.md   机制说明、各版本改动、反编译证据、实机验证记录、安装步骤

依赖环境：apktool、uber-apk-signer、jdk4py(JRE)、Python（见 build_app.py 内路径）。
设备要求：Boyue Likebook K103 / Android 8.1 / arm64 / Magisk root（无需 Xposed）。