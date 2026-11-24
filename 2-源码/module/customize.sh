#!/sbin/sh
# Magisk 安装脚本（系统运行时执行）
ui_print " "
ui_print "- K103 透明锁屏 v1.6（亮屏预合成 + 规避 HWC 默认图）"
ui_print "- 适用: Boyue Likebook K103 / Android 8.1 / arm64 / 已 root+面具"

set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in img2raw_k103 compose_k103; do
  [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
for f in service.sh uninstall.sh action.sh tools/lockscreen_ctl.sh; do
  [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
for f in enabled config.conf settings.conf settings.default.conf; do
  [ -f "$MODPATH/$f" ] && chmod 666 "$MODPATH/$f" 2>/dev/null
done
[ -f "$MODPATH/enabled" ] || echo 1 > "$MODPATH/enabled"

# ---- 升级：保留旧版配置 / 备份 / 洗牌队列（避免升级后重洗、丢原厂图备份）----
OLD=/data/adb/modules/k103_transparent_lockscreen
if [ -d "$OLD" ]; then
  if [ -f "$OLD/settings.conf" ]; then
    cp -f "$OLD/settings.conf" "$MODPATH/settings.conf" 2>/dev/null
    for kv in 'BROADCAST="0"' 'PRECOMPOSE="1"' 'COMPOSE_MIN_GAP="2"' 'FORCE_STANDBYSETTING="1"'; do
      k=${kv%%=*}
      grep -q "^$k=" "$MODPATH/settings.conf" 2>/dev/null || echo "$kv" >> "$MODPATH/settings.conf"
    done
    ui_print "- 已保留旧设置 settings.conf（并补齐 v1.6 新项）"
  fi
  if [ -d "$OLD/backup" ]; then
    rm -rf "$MODPATH/backup" 2>/dev/null
    cp -rf "$OLD/backup" "$MODPATH/" 2>/dev/null
  fi
  for f in current_image.txt pending_image.txt .shuffle_queue .shuffle_idx .shuffle_sig; do
    [ -f "$OLD/$f" ] && cp -f "$OLD/$f" "$MODPATH/$f" 2>/dev/null
  done
  for f in settings.conf enabled; do
    [ -f "$MODPATH/$f" ] && chmod 666 "$MODPATH/$f" 2>/dev/null
  done
fi

# 图库目录（本包不含任何图片）；旧目录自动迁移，图片不丢
IMGDIR=/sdcard/Pictures/K103_Lockscreen
OLDIMG=/sdcard/Pictures/A5Pro_Lockscreen
if [ ! -d "$IMGDIR" ] && [ -d "$OLDIMG" ]; then
  mv "$OLDIMG" "$IMGDIR" 2>/dev/null
  ui_print "- 已迁移旧图库目录 -> K103_Lockscreen"
fi
mkdir -p "$IMGDIR" 2>/dev/null
if [ -d "$IMGDIR" ]; then
  cat > "$IMGDIR/PUT-IMAGES-HERE.txt" <<'EOT'
请把锁屏图片放进本目录（PNG / JPG / JPEG，支持一层子目录）。
至少放 1 张，建议 2 张以上；默认 fit 模式等比居中，
随机模式会透出锁屏前最后一帧（BG_MODE=lastframe）。
前后不重复；想铺满整屏可把 SCALE 改成 cover。
EOT
  chmod 664 "$IMGDIR/PUT-IMAGES-HERE.txt" 2>/dev/null
  chown -R media_rw:media_rw "$IMGDIR" 2>/dev/null
  ui_print "- 图库目录: $IMGDIR"
  ui_print "  !! 请自行放入至少 1 张 PNG/JPG，否则不会随机换图"
fi

# 配套控制端 App（若 zip 内附带则提示用户手动安装）
if [ -f "$MODPATH/apps/猫猫透明锁屏forAlita-v1.1.apk" ]; then
  ui_print "- 附带控制端 App: apps/猫猫透明锁屏forAlita-v1.1.apk"
  ui_print "  请在文件管理器中点击安装（需授权 root）"
fi

# 备份该机自己的原厂锁屏图，供卸载还原（包内不带图片）
mkdir -p "$MODPATH/backup" 2>/dev/null
if [ -f /data/misc/standby.jpg ] && [ ! -f "$MODPATH/backup/standby.orig.jpg" ]; then
  cp /data/misc/standby.jpg "$MODPATH/backup/standby.orig.jpg" 2>/dev/null
  ui_print "- 已备份原厂锁屏图（卸载时还原）"
fi

ui_print "- 本模块不修改 EPD/HWC/boot；重启后 daemon 自动运行"
ui_print " "