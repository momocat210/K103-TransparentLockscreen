K103 透明锁屏 v1.6
=====================================
适用: Boyue Likebook K103 / Android 8.1 / arm64 / 已 root + Magisk

v1.6 修复
----------
1) 连续同一画面锁屏总是同一张壁纸：
   反编译 /vendor/lib64/hw/hwcomposer.rk30board.so 发现，熄屏绘制待机图前会读
   sys.by.standbysetting；若为 1（Settings 的 WallpaperTask 正在设壁纸），
   HWC 会跳过 /data/misc/standby.jpg，直接画 /system/media/standby.jpg 默认图。
   旧版 v1.5 熄屏后发 SET_WALLPAPER 广播，会把该属性置 1 并持续 2~4 秒，
   连续熄屏时正好撞进窗口 -> 反复显示同一张默认图。
   v1.6 不再发广播，直接原子替换 standby.jpg；启动/LOCK 时把属性归零。

2) 透出部分不是锁屏前画面：
   旧版熄屏后 2~3 秒才写图，而 HWC 在熄屏瞬间已读完文件，显示的是上一张。
   v1.6 亮屏期间“预合成”：抓到的帧一变，就用「待显示贴纸 + 最新帧」合成并
   原子替换 standby.jpg；熄屏时再准备下一张贴纸，连续锁屏也会轮换。

3) 新增 framecmp_k103：抓帧在内存比较，画面没变就不写 10MB，保护 eMMC。

效果
----
每次锁屏（熄屏）时，把当前选图以合成方式写入系统锁屏图
/data/misc/standby.jpg（并同步副本 /data/misc/temp.jpg）。
- 随机换图（SHUFFLE=1，默认）：洗牌队列一轮内每张恰好一次，跨轮避重；
  透明区透出锁屏前最后一帧。
- 固定贴纸（SHUFFLE=0）：一直用同一张贴纸。
- 纯白底（BG_MODE=white）：不透出画面。

安装
----
1. 面具 → 模块 → 从本地安装 → 选中本 zip → 重启。
2. 把至少 1 张 PNG/JPG 放进 /sdcard/Pictures/K103_Lockscreen/
   （建议 2 张以上；支持一层子目录）。旧目录 A5Pro_Lockscreen 会自动迁移。
3. 重启后每次按电源键熄屏即随机换图。

设置（推荐配套 App「猫猫透明锁屏forAlita」v1.2，按钮全圆角）
------------------------------------------------------------
- 随机/固定、fit/cover/stretch、纯白底/透出上一帧
- JPEG 质量、抓帧频率（0.5 / 1 / 2 秒）
- 立即换一张、图库列表、日志、恢复默认、还原原厂图、启用/停用

命令行
------
sh /data/adb/modules/k103_transparent_lockscreen/tools/lockscreen_ctl.sh status
... next | enable 0/1 | reset | mkdir | gallery | log | restore
... set SCALE cover | set SHUFFLE 0 | set JPEG_QUALITY 95
... set BG_MODE white | set TRACK_EVERY 2
... set BROADCAST 1 | set PRECOMPOSE 0 | set FORCE_STANDBYSETTING 0

说明
----
- 不修改 EPD 波形 / HWC / SystemUI / boot，只写 standby.jpg + temp.jpg。
- 首次安装会备份本机原厂锁屏图到模块 backup/，卸载自动还原。
- 包内不含任何图片素材。