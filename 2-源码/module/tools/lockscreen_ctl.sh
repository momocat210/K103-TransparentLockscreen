#!/system/bin/sh
# K103 透明锁屏 v1.6 控制接口（root 调用）
# 用法: sh lockscreen_ctl.sh <status|set KEY VAL|next|enable 0/1|reset|gallery|log|apply|restore>
MOD=/data/adb/modules/k103_transparent_lockscreen
CONF=$MOD/settings.conf
[ -f "$CONF" ] && . "$CONF"

case "$1" in
  status)
    echo "---CONF---"
    grep -v '^#' "$CONF" 2>/dev/null
    echo "---COUNT---"
    find "$IMAGE_DIR" -maxdepth 2 -type f 2>/dev/null | grep -icE '\.(png|jpg|jpeg)$'
    echo "---CURRENT---"
    cat "$MOD/current_image.txt" 2>/dev/null || echo '(未选图)'
    echo "---PENDING---"
    cat "$MOD/pending_image.txt" 2>/dev/null || echo '(无)'
    echo "---LAST---"
    cat "$MOD/last_update.txt" 2>/dev/null || echo '(无)'
    echo "---STANDBY---"
    ls -l /data/misc/standby.jpg 2>/dev/null
    md5sum /data/misc/standby.jpg 2>/dev/null
    echo "---SETTING---"
    getprop sys.by.standbysetting 2>/dev/null
    echo "---ENABLED---"
    cat "$MOD/enabled" 2>/dev/null
    echo "---DAEMON---"
    DP=$(cat "$MOD/daemon.pid" 2>/dev/null)
    if [ -n "$DP" ] && kill -0 "$DP" 2>/dev/null; then echo "running pid=$DP"; else echo "stopped"; fi
    echo "---WAKE---"
    dumpsys power 2>/dev/null | grep -m1 'mWakefulness=' | tr -d ' \r'
    echo "---FULLREFRESH---"
    getprop sys.by.app.fullrefresh 2>/dev/null
    echo "---VER---"
    grep -E '^(version|versionCode)=' "$MOD/module.prop" 2>/dev/null
    ;;
  set)
    K=$2; V=$3
    case "$K" in
      IMAGE_DIR|SCALE|SHUFFLE|BG_MODE|JPEG_QUALITY|AVOID_RECENT|INTERVAL|USE_FULLREFRESH|TRACK_EVERY|BROADCAST|PRECOMPOSE|COMPOSE_MIN_GAP|FORCE_STANDBYSETTING) ;;
      *) echo "BAD_KEY"; exit 1 ;;
    esac
    if [ -z "$V" ] || echo "$V" | grep -q '[^A-Za-z0-9_/. -]'; then
      echo "BAD_VALUE"; exit 1
    fi
    if grep -q "^$K=" "$CONF"; then
      sed -i "s|^$K=.*|$K=\"$V\"|" "$CONF"
    else
      echo "$K=\"$V\"" >> "$CONF"
    fi
    echo "OK $K=$V"
    ;;
  next)
    touch "$MOD/next.flag"
    echo "OK next"
    ;;
  enable)
    case "$2" in
      0|1) echo "$2" > "$MOD/enabled"; echo "OK enabled=$2" ;;
      *) echo "BAD_VALUE"; exit 1 ;;
    esac
    ;;
  reset)
    cp "$MOD/settings.default.conf" "$CONF"
    echo 1 > "$MOD/enabled"
    echo "OK reset"
    ;;
  mkdir)
    mkdir -p "$IMAGE_DIR"; chmod 777 "$IMAGE_DIR" 2>/dev/null
    echo "OK $IMAGE_DIR"
    ;;
  gallery)
    find "$IMAGE_DIR" -maxdepth 2 -type f 2>/dev/null | grep -iE '\.(png|jpg|jpeg)$' | sort | head -60
    ;;
  log)
    tail -40 "$MOD/service.log" 2>/dev/null
    ;;
  apply)
    # 用当前选图立即合成写入（不换图）
    touch "$MOD/next.flag"
    echo "OK apply queued"
    ;;
  restore)
    # 还原原厂锁屏图
    if [ -f "$MOD/backup/standby.orig.jpg" ]; then
      TMP=/data/local/tmp/.restore.$$
      cat "$MOD/backup/standby.orig.jpg" > "$TMP" 2>/dev/null
      mv -f "$TMP" /data/misc/standby.jpg 2>/dev/null || cat "$MOD/backup/standby.orig.jpg" > /data/misc/standby.jpg
      cp -f /data/misc/standby.jpg /data/misc/temp.jpg 2>/dev/null
      chown system:system /data/misc/standby.jpg /data/misc/temp.jpg 2>/dev/null
      chmod 600 /data/misc/standby.jpg /data/misc/temp.jpg 2>/dev/null
      restorecon /data/misc/standby.jpg /data/misc/temp.jpg >/dev/null 2>&1
      rm -f "$TMP"
      # 一次性通知系统（同时把 standbysetting 复位，避免影响下次熄屏）
      am broadcast -a com.boyue.action.SET_WALLPAPER -f 0x01000000 --es filePath /data/misc/standby.jpg >/dev/null 2>&1
      sleep 1
      setprop sys.by.standbysetting 0 2>/dev/null
      echo "OK restored"
    else
      echo "NO_BACKUP"
    fi
    ;;
  *)
    echo "usage: lockscreen_ctl.sh status|set KEY VAL|next|enable 0/1|reset|mkdir|gallery|log|apply|restore"
    exit 1
    ;;
esac