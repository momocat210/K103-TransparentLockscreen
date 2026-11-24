#!/system/bin/sh
# K103 透明锁屏 v1.6 —— 洗牌随机图库 + 锁屏前最后一帧透出
# Magisk late_start service, root 运行, 不阻塞开机。
#
# ===== 运行机制（实机确认）=====
#   K103 的系统待机/锁屏图 = /data/misc/standby.jpg (JPEG, system:system 600)
#   熄屏时由 HWC（/vendor/lib64/hw/hwcomposer.rk30board.so 的 drawStandbyLogo）
#   读取该文件并绘制到 EPD。读取优先级：
#     /data/misc/standby.jpg > /data/misc/standby.png > /system/media/standby.jpg
#
# ===== v1.6 关键修复（连续锁屏同一张 / 透出不是锁屏前画面）=====
#   1) 反汇编 hwcomposer 发现：drawStandbyLogo 绘制前会读系统属性
#      sys.by.standbysetting，若值为 1（Settings 的 WallpaperTask 正在设壁纸），
#      会【跳过自定义图，直接画 /system/media/standby.jpg 默认图】。
#      旧版每次熄屏后发 com.boyue.action.SET_WALLPAPER 广播，触发 WallpaperTask
#      把该属性置 1 并持续 2~4 秒；用户连续熄屏/亮屏时正好撞进窗口
#      -> 锁屏反复显示默认图，看起来就是“同一张壁纸”。
#   2) 旧版 daemon 在熄屏后 2~3 秒才写入新图，而 HWC 在熄屏瞬间就已读完文件
#      -> 每次显示的是上一张，透出的是上一次锁屏前的画面。
#
#   修复：
#     a. 熄屏后不再发广播（避免 standbysetting=1，也避免系统重编码 1.3MB）；
#        直接原子替换 /data/misc/standby.jpg，HWC 每次熄屏都会重新 fopen。
#     b. 亮屏期间“预合成”：抓到的帧一旦变化，立即用【待显示贴纸 + 最新帧】
#        合成并原子写入 standby.jpg。熄屏瞬间 HWC 读到的就是锁屏前最后一帧。
#     c. 熄屏时选下一张贴纸并立即合成写入，保证“亮屏不解锁直接再熄屏”也能轮换。
#     d. 启动 / LOCK 时把 sys.by.standbysetting 归零，杜绝默认图。
#     e. 默认 TRACK_EVERY=1（约 0.5 秒抓一帧），锁屏前画面误差更小。
#
# ===== 历史改动 =====
#   v1.2 亮屏持续抓帧，熄屏用最新帧合成（修复“透出更早内容”）
#   v1.3 随机模式也可透出上一帧；APP 增加抓帧频率三档
#   v1.4 选图改为洗牌队列（一轮内每张恰好一次，跨轮避重）
#   v1.5 广播加 FLAG_RECEIVER_FOREGROUND，避免被 Android 8.1 后台限制拦截
#   v1.6 不再广播 + 亮屏预合成 + 原子替换 + standbysetting 归零（见上）
MODDIR=${0%/*}

STANDBY=/data/misc/standby.jpg
TEMPJ=/data/misc/temp.jpg
IMG2RAW=$MODDIR/img2raw_k103
COMPOSE=$MODDIR/compose_k103
FRAMECMP=$MODDIR/framecmp_k103
LOG=$MODDIR/service.log
CURIMG=$MODDIR/current_image.txt
PENDINGIMG=$MODDIR/pending_image.txt
LIST=$MODDIR/.imglist
QUEUE=$MODDIR/.shuffle_queue
QIDX=$MODDIR/.shuffle_idx
QSIG=$MODDIR/.shuffle_sig
RECENT=$MODDIR/.recent_picks
STK=$MODDIR/current.raw
PENDING=$MODDIR/pending.raw
FRAME=$MODDIR/frame.raw
FRAMETMP=$MODDIR/.frame.tmp
STKTMP=$MODDIR/.pending.tmp
OUTTMP=$MODDIR/.out.tmp
NEXTFLAG=$MODDIR/next.flag

# --- 默认值（settings.conf 由设置 App 写入并可覆盖） ---
IMAGE_DIR=/sdcard/Pictures/K103_Lockscreen
SHUFFLE=1
SCALE=fit
BG_MODE=lastframe
JPEG_QUALITY=92
AVOID_RECENT=3
INTERVAL=3
# 抓帧间隔(轮): 1=每轮约0.5s(最贴近锁屏前画面,默认); 2=约1s; 4=约2s(省电但滞后)
TRACK_EVERY=1
POLL=0.5
# 局刷开关: 熄屏期间用 Boyue 现成全局属性 sys.by.app.fullrefresh 控制刷新观感
# 0=不碰(默认,最安全) 1=熄屏期间置 1 请求全刷, 亮屏还原
USE_FULLREFRESH=0
FULLREFRESH_PROP=sys.by.app.fullrefresh
# --- v1.6 新增 ---
# 1=熄屏后仍发 SET_WALLPAPER 前台广播（旧版行为，会触发 standbysetting=1，不推荐）
BROADCAST=0
# 1=亮屏期间帧变化就预合成写入 standby.jpg（推荐，保证透出锁屏前画面）
PRECOMPOSE=1
# 预合成最小间隔(秒)，防止滚动/动画时高频重编码
COMPOSE_MIN_GAP=2
# 1=启动和熄屏时把 sys.by.standbysetting 归零（防止 HWC 画默认图）
FORCE_STANDBYSETTING=1
[ -f "$MODDIR/config.conf" ] && . "$MODDIR/config.conf"
[ -f "$MODDIR/settings.conf" ] && . "$MODDIR/settings.conf"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; chmod 644 "$LOG" 2>/dev/null; }

# --- 开机等待 ---
n=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $n -lt 90 ]; do sleep 2; n=$((n+1)); done
echo "started $(date '+%F %T') v1.6 poll=${POLL}s track_every=${TRACK_EVERY} scale=$SCALE bg=$BG_MODE shuffle=$SHUFFLE q=$JPEG_QUALITY bc=$BROADCAST pre=$PRECOMPOSE" > "$LOG"
chmod 644 "$LOG" 2>/dev/null
echo $$ > "$MODDIR/daemon.pid"
chmod 644 "$MODDIR/daemon.pid" 2>/dev/null

# 记录原图权限/属主, 卸载时按此还原
if [ -f "$STANDBY" ] && [ ! -f "$MODDIR/orig_perm.txt" ]; then
  stat -c '%U:%G %a' "$STANDBY" > "$MODDIR/orig_perm.txt" 2>/dev/null || echo 'system:system 600' > "$MODDIR/orig_perm.txt"
fi
# 首次装入备份该机自己的锁屏图供卸载还原（包内不带任何图片）
if [ -f "$STANDBY" ] && [ ! -f "$MODDIR/backup/standby.orig.jpg" ]; then
  mkdir -p "$MODDIR/backup"
  cp "$STANDBY" "$MODDIR/backup/standby.orig.jpg" 2>/dev/null
  log "backed up original standby.jpg"
fi

# 迁移旧目录: 若旧的 A5Pro_Lockscreen 存在而新目录不存在，自动更名，用户图库不丢
OLD_DIR=/sdcard/Pictures/A5Pro_Lockscreen
if [ ! -d "$IMAGE_DIR" ] && [ -d "$OLD_DIR" ]; then
  mkdir -p "$(dirname "$IMAGE_DIR")"
  mv "$OLD_DIR" "$IMAGE_DIR" 2>/dev/null && log "migrated gallery $OLD_DIR -> $IMAGE_DIR"
fi

FULLREFRESH_ORIG=""
restore_fullrefresh() {
  [ -n "$FULLREFRESH_ORIG" ] || return 0
  setprop "$FULLREFRESH_PROP" "$FULLREFRESH_ORIG" 2>/dev/null
  FULLREFRESH_ORIG=""
  log "fullrefresh restored"
}

# 重建洗牌队列：给每张图加随机前缀后按数字排序，去掉前缀即得打乱顺序。
# 只用系统自带的 sed/sort/cut（K103 toybox 无 awk/shuf/sort -R，勿用）。
# 边界保证：若队首 == 上一张，把队首与队尾交换，避免跨轮相邻重复。
rebuild_queue() {
  [ -s "$LIST" ] || return 1
  : > "$QUEUE.tmp"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    R=$(( (RANDOM * 32768) + RANDOM ))
    printf '%s\t%s\n' "$R" "$line" >> "$QUEUE.tmp"
  done < "$LIST"
  sort -n "$QUEUE.tmp" | cut -f2- > "$QUEUE"
  rm -f "$QUEUE.tmp"
  N=$(wc -l < "$QUEUE")
  [ "$N" -gt 0 ] || return 1
  echo 1 > "$QIDX"
  md5sum "$LIST" | cut -d' ' -f1 > "$QSIG"

  LAST=$(cat "$PENDINGIMG" 2>/dev/null)
  [ -n "$LAST" ] || LAST=$(cat "$CURIMG" 2>/dev/null)
  if [ -n "$LAST" ] && [ "$N" -gt 1 ]; then
    FIRST=$(sed -n '1p' "$QUEUE")
    if [ "$FIRST" = "$LAST" ]; then
      {
        tail -n 1 "$QUEUE"
        sed -n "2,$((N-1))p" "$QUEUE"
        echo "$FIRST"
      } > "$QUEUE.tmp2"
      mv "$QUEUE.tmp2" "$QUEUE"
      log "queue head==last, swapped with tail to avoid cross-round repeat"
    fi
  fi
  log "queue rebuilt: $N images shuffled"
  return 0
}

# 从洗牌队列取下一张，解码为 RGBA 到 pending.raw（不立即显示）。
# 一轮内每张恰好一次；队尾后自动重洗，并避免跨轮首张 == 上一张。
pick_next() {
  [ -d "$IMAGE_DIR" ] || { log "IMAGE_DIR missing: $IMAGE_DIR"; return 1; }
  find "$IMAGE_DIR" -maxdepth 2 -type f 2>/dev/null | grep -iE '\.(png|jpg|jpeg)$' | sort > "$LIST"
  N=$(wc -l < "$LIST")
  [ "$N" -gt 0 ] || { log "no png/jpg in $IMAGE_DIR"; return 1; }

  SIG=$(md5sum "$LIST" | cut -d' ' -f1)
  OLDSIG=$(cat "$QSIG" 2>/dev/null)
  QLEN=0
  [ -s "$QUEUE" ] && QLEN=$(wc -l < "$QUEUE")
  IDX=$(cat "$QIDX" 2>/dev/null)
  case "$IDX" in ''|*[!0-9]*) IDX=0 ;; esac
  if [ "$SIG" != "$OLDSIG" ] || [ "$QLEN" -ne "$N" ] || [ "$IDX" -lt 1 ] || [ "$IDX" -gt "$N" ]; then
    rebuild_queue || return 1
    IDX=1
  fi

  TRY=0
  while [ "$TRY" -lt "$N" ]; do
    PICK=$(sed -n "${IDX}p" "$QUEUE")
    # 兜底：队列里这一行若已不在当前图库(极端情况)，重洗重取
    if [ -z "$PICK" ] || ! grep -qxF "$PICK" "$LIST"; then
      rebuild_queue || return 1
      IDX=1
      PICK=$(sed -n '1p' "$QUEUE")
      [ -n "$PICK" ] || return 1
    fi

    NEXTIDX=$((IDX + 1))
    if [ "$NEXTIDX" -gt "$N" ]; then
      # 本轮结束：先记录本次选的图，重洗时会避开它作为队首
      echo "$PICK" > "$PENDINGIMG"
      rebuild_queue
      NEXTIDX=1
    fi

    if "$IMG2RAW" "$PICK" "$SCALE" > "$STKTMP" 2>>"$LOG" && [ "$(wc -c < "$STKTMP")" = "10513152" ]; then
      mv -f "$STKTMP" "$PENDING"
      echo "$PICK" > "$PENDINGIMG"
      echo "$NEXTIDX" > "$QIDX"
      { [ -s "$RECENT" ] && tail -n 20 "$RECENT"; echo "$PICK"; } > "$RECENT.tmp"
      mv "$RECENT.tmp" "$RECENT"
      log "queued [$(basename "$PICK")] (queue $IDX/$N)"
      return 0
    fi
    rm -f "$STKTMP"
    echo "$NEXTIDX" > "$QIDX"
    log "decode FAILED [$PICK], skipped"
    IDX=$NEXTIDX
    TRY=$((TRY + 1))
  done
  return 1
}

# 判断帧是否全黑（熄屏竞态下 screencap 会得到纯黑帧，必须丢弃）
frame_is_black() {
  local f=$1 s
  for off in 2628304 5256592 7884880; do
    s=$(dd if="$f" bs=1 skip=$off count=64 2>/dev/null | od -An -tu1 | tr -d ' \n')
    case "$s" in *[1-9]*) return 1 ;; esac
  done
  return 0
}

# 缓存当前亮屏帧作为"透出底图"。
# 返回 0=帧有更新, 1=无变化/失败（无变化时不触发预合成）
# 优先用 framecmp_k103：从管道读帧、与缓存逐字节比较，只在真的变化时才写 10MB，
# 静止画面下几乎零 eMMC 写入（旧版每 0.5s 写 10MB，长期会磨损闪存）。
cache_frame() {
  if [ -x "$FRAMECMP" ]; then
    screencap 2>>"$LOG" | "$FRAMECMP" "$FRAME" 2>>"$LOG"
    case $? in
      0) return 0 ;;
      1) return 1 ;;
      3) log "track frame: black frame ignored"; return 1 ;;
      4) log "track frame: boot white frame ignored"; return 1 ;;
      *) log "track frame: screencap failed"; return 1 ;;
    esac
  fi
  screencap > "$FRAMETMP" 2>>"$LOG"
  if [ "$(wc -c < "$FRAMETMP")" != "10513168" ]; then
    rm -f "$FRAMETMP"
    log "track frame: screencap failed"
    return 1
  fi
  if frame_is_black "$FRAMETMP"; then
    rm -f "$FRAMETMP"
    log "track frame: black frame ignored"
    return 1
  fi
  if [ -s "$FRAME" ] && cmp -s "$FRAMETMP" "$FRAME"; then
    rm -f "$FRAMETMP"
    return 1
  fi
  mv -f "$FRAMETMP" "$FRAME"
  return 0
}

# 原子替换锁屏图（HWC 以 fopen 读取，rename 不会读到半截文件）
install_standby() {
  local src=$1
  if mv -f "$src" "$STANDBY" 2>/dev/null; then
    :
  else
    cat "$src" > "$STANDBY" 2>/dev/null || { rm -f "$src"; return 1; }
    rm -f "$src"
  fi
  chown system:system "$STANDBY" 2>/dev/null
  chmod 600 "$STANDBY" 2>/dev/null
  restorecon "$STANDBY" >/dev/null 2>&1
  cp -f "$STANDBY" "$TEMPJ" 2>/dev/null
  chown system:system "$TEMPJ" 2>/dev/null
  chmod 600 "$TEMPJ" 2>/dev/null
  restorecon "$TEMPJ" >/dev/null 2>&1
  return 0
}

# 合成并写入系统锁屏图
#   底图：BG_MODE=lastframe 且有缓存帧 -> frame.raw；否则白底
#   贴纸：pending.raw（待显示的下一张），没有则退回 current.raw
compose_now() {
  local sticker=$PENDING base=$MODDIR/frame_white.raw img basekind
  [ -s "$sticker" ] || sticker=$STK
  if [ ! -s "$sticker" ]; then
    log "compose skipped: no sticker raw"
    return 1
  fi
  if [ "$BG_MODE" = "lastframe" ] && [ -s "$FRAME" ]; then
    base=$FRAME
    basekind=lastframe
  else
    basekind=white
  fi
  [ -s "$base" ] || return 1
  if ! "$COMPOSE" "$sticker" "$base" "$OUTTMP" "$JPEG_QUALITY" 1 >>"$LOG" 2>&1 || [ ! -s "$OUTTMP" ]; then
    rm -f "$OUTTMP"
    log "compose FAILED"
    return 1
  fi
  install_standby "$OUTTMP" || { log "install standby FAILED"; return 1; }

  img=$(cat "$PENDINGIMG" 2>/dev/null)
  cp -f "$PENDING" "$STK" 2>/dev/null
  date '+%F %T' > "$MODDIR/last_update.txt"
  log "applied standby.jpg ($(wc -c < "$STANDBY") B, mode=$BG_MODE shuffle=$SHUFFLE base=$basekind img=$(basename "${img:-none}"))"

  # v1.5 行为兼容开关：默认关闭（广播会让 standbysetting=1 -> HWC 画默认图）
  if [ "$BROADCAST" = "1" ]; then
    am broadcast -a com.boyue.action.SET_WALLPAPER -f 0x01000000 --es filePath "$STANDBY" >/dev/null 2>&1
  fi
  return 0
}

# 当前是否有 Keyguard 遮挡（K103 无 mIsShowing, 用 isStatusBarKeyguard 判断）
# 返回 0=无锁屏遮挡(可安全抓帧), 1=锁屏显示中或未知(跳过抓帧)
keyguard_hidden() {
  # 该行形如 "mStatusBar=Window{...} isStatusBarKeyguard=false", 需用 -o 取纯值
  KG=$(dumpsys window policy 2>/dev/null | grep -o 'isStatusBarKeyguard=[a-z]*' | head -1)
  [ "$KG" = "isStatusBarKeyguard=false" ] && return 0
  return 1
}

# ===== 启动自检 =====
# 上次 WallpaperTask 若异常退出，属性可能卡在 1 -> HWC 会画默认图
if [ "$FORCE_STANDBYSETTING" = "1" ] && [ "$(getprop sys.by.standbysetting 2>/dev/null)" = "1" ]; then
  setprop sys.by.standbysetting 0 2>/dev/null
  log "reset sys.by.standbysetting at boot"
fi

# 上次运行留下的缓存帧可能对应已经消失的界面（重启后更是如此），
# 先丢掉，等亮屏后抓到第一帧有效画面再预合成。
rm -f "$FRAME" "$FRAMETMP"

# 立即准备第一张；有缓存帧才合成（没有帧时保留现有 standby.jpg，
# 避免开机白屏/过渡帧被固化，等第一次有效帧再预合成）
if [ ! -s "$PENDING" ]; then
  pick_next || log "initial pick failed"
fi
if [ -s "$FRAME" ]; then
  compose_now || log "initial compose failed"
else
  log "no cached frame yet, keep current standby.jpg until first valid frame"
fi

PREV_WAKE=$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=' | tr -d ' \r')
LAST_HEAVY=0
TRACK_TICK=0
LAST_COMPOSE=$(date +%s)
# 自适应抓帧：检测到画面变化后 20 秒内按 0.5 秒高频跟随（翻页/滚动），
# 静止时回到用户设定的 TRACK_EVERY，兼顾贴合度与功耗。
FAST_UNTIL=0

while :; do
  [ -f "$MODDIR/disable" ] && break
  [ -f "$MODDIR/remove" ] && break

  WAKE=$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=' | tr -d ' \r')
  NOW=$(date +%s)
  TRACK_TICK=$(( TRACK_TICK + 1 ))

  # 熄屏瞬间 / 亮屏瞬间
  if [ "$WAKE" != "$PREV_WAKE" ] && [ -n "$WAKE" ]; then
    if [ "$PREV_WAKE" = "mWakefulness=Awake" ] && [ "$WAKE" != "mWakefulness=Awake" ]; then
      log "=== LOCK event ($WAKE) ==="
      if [ "$(cat "$MODDIR/enabled" 2>/dev/null)" = "1" ]; then
        if [ "$USE_FULLREFRESH" = "1" ]; then
          FULLREFRESH_ORIG=$(getprop "$FULLREFRESH_PROP" 2>/dev/null)
          setprop "$FULLREFRESH_PROP" 1 2>/dev/null
        fi
        # 关键修复：HWC 绘制前若 standbysetting=1 会画默认图
        if [ "$FORCE_STANDBYSETTING" = "1" ] && [ "$(getprop sys.by.standbysetting 2>/dev/null)" != "0" ]; then
          setprop sys.by.standbysetting 0 2>/dev/null
          log "forced sys.by.standbysetting=0 before draw"
        fi
        # 本次锁屏显示的就是上一次已写入 standby.jpg 的那张，记为「当前」
        [ -s "$PENDINGIMG" ] && cp -f "$PENDINGIMG" "$CURIMG" 2>/dev/null
        # 选下一张贴纸并立即合成：本次若已被 HWC 读取则作为下一次的图，
        # 保证“亮屏不解锁直接再熄屏”也能轮换。
        if [ "$SHUFFLE" = "1" ]; then pick_next; fi
        compose_now || log "apply skipped at lock"
        LAST_COMPOSE=$(date +%s)
      else
        log "module disabled, skip lock image"
      fi
    elif [ "$PREV_WAKE" != "mWakefulness=Awake" ] && [ "$WAKE" = "mWakefulness=Awake" ]; then
      log "=== UNLOCK event ==="
      [ "$USE_FULLREFRESH" = "1" ] && restore_fullrefresh
    fi
    PREV_WAKE=$WAKE
  fi

  # 重活: 读配置热加载 / 立即换一张 / 属性守护
  if [ $(( NOW - LAST_HEAVY )) -ge "$INTERVAL" ]; then
    LAST_HEAVY=$NOW
    [ -f "$MODDIR/settings.conf" ] && . "$MODDIR/settings.conf"

    # 属性守护：WallpaperTask 若正在运行会把 sys.by.standbysetting 置 1，
    # HWC 见到 1 就会画默认图。趁熄屏前提前归零，避免撞窗口。
    if [ "$FORCE_STANDBYSETTING" = "1" ] && [ "$(getprop sys.by.standbysetting 2>/dev/null)" = "1" ]; then
      setprop sys.by.standbysetting 0 2>/dev/null
      log "kept sys.by.standbysetting=0"
    fi

    if [ -f "$NEXTFLAG" ]; then
      rm -f "$NEXTFLAG"
      log "forced next image"
      if pick_next; then
        compose_now
        LAST_COMPOSE=$(date +%s)
      fi
    fi
  fi

  # 高频跟随缓存帧: 亮屏且无 Keyguard 时, 每 TRACK_EVERY 轮(约 POLL 秒)抓一帧。
  # 帧一旦变化就立即预合成写入 standby.jpg，熄屏时 HWC 读到的就是最新画面。
  case "$TRACK_EVERY" in ''|*[!0-9]*) TRACK_EVERY=1 ;; esac
  [ "$TRACK_EVERY" -lt 1 ] && TRACK_EVERY=1
  EFF=$TRACK_EVERY
  [ "$NOW" -lt "$FAST_UNTIL" ] && [ "$EFF" -gt 1 ] && EFF=1
  if [ $(( TRACK_TICK % EFF )) -eq 0 ]; then
    if [ "$BG_MODE" = "lastframe" ] &&
       [ "$(cat "$MODDIR/enabled" 2>/dev/null)" = "1" ] &&
       [ "$WAKE" = "mWakefulness=Awake" ]; then
      if keyguard_hidden; then
        if cache_frame; then
          FAST_UNTIL=$(( NOW + 20 ))
          if [ "$PRECOMPOSE" = "1" ] && [ -s "$PENDING" ]; then
            NOW2=$(date +%s)
            if [ $(( NOW2 - LAST_COMPOSE )) -ge "$COMPOSE_MIN_GAP" ]; then
              compose_now
              LAST_COMPOSE=$(date +%s)
            fi
          fi
        fi
      fi
    fi
  fi

  sleep "$POLL"
done

[ "$USE_FULLREFRESH" = "1" ] && restore_fullrefresh
log "daemon stopped"