#!/system/bin/sh
# 卸载还原：恢复原厂锁屏图 + 恢复局刷属性
MODDIR=${0%/*}
STANDBY=/data/misc/standby.jpg
TEMPJ=/data/misc/temp.jpg

if [ -f "$MODDIR/backup/standby.orig.jpg" ]; then
  TMP=/data/local/tmp/.uninstall_restore.$$
  cp -f "$MODDIR/backup/standby.orig.jpg" "$TMP" 2>/dev/null || cat "$MODDIR/backup/standby.orig.jpg" > "$TMP" 2>/dev/null
  if [ -s "$TMP" ]; then
    mv -f "$TMP" "$STANDBY" 2>/dev/null || cat "$TMP" > "$STANDBY" 2>/dev/null
    rm -f "$TMP"
  fi
  cp -f "$STANDBY" "$TEMPJ" 2>/dev/null
  if [ -f "$MODDIR/orig_perm.txt" ]; then
    set -- $(cat "$MODDIR/orig_perm.txt")
    [ -n "$1" ] && chown "$1" "$STANDBY" "$TEMPJ" 2>/dev/null
    [ -n "$2" ] && chmod "$2" "$STANDBY" "$TEMPJ" 2>/dev/null
  else
    chown system:system "$STANDBY" "$TEMPJ" 2>/dev/null
    chmod 600 "$STANDBY" "$TEMPJ" 2>/dev/null
  fi
  restorecon "$STANDBY" "$TEMPJ" >/dev/null 2>&1
fi
setprop sys.by.app.fullrefresh 0 2>/dev/null
am broadcast -a com.boyue.action.SET_WALLPAPER -f 0x01000000 --es filePath /data/misc/standby.jpg >/dev/null 2>&1
sleep 1
setprop sys.by.standbysetting 0 2>/dev/null
exit 0