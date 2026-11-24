#!/system/bin/sh
# 面具 → 模块 → 「操作」：立即换一张锁屏图
ctl=/data/adb/modules/k103_transparent_lockscreen/tools/lockscreen_ctl.sh
[ -f "$ctl" ] && sh "$ctl" next
exit 0
