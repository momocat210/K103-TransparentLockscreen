#!/usr/bin/env python3
"""打包 K103 透明锁屏 Magisk 模块为可刷入的 flashable zip（v1.6）。

v1.6 起使用标准 Magisk 模块结构：
  - module.prop / service.sh / customize.sh 等直接位于 zip 根目录
  - META-INF 使用 Magisk 的 install_module 安装流程
  - apps/*.apk 随包分发（customize.sh 里提示手动安装）
"""
import os, zipfile, hashlib

ROOT = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.join(ROOT, "module")
APPS = os.path.join(ROOT, "apps")
OUT = os.path.join(ROOT, "K103-TransparentLockscreen-v1.6.zip")

UPDATE_BINARY = r'''#!/sbin/sh
umask 022
OUTFD=$2
ZIPFILE=$3

mount /data 2>/dev/null

[ -f /data/adb/magisk/util_functions.sh ] || {
  echo "! Magisk not found, abort"
  exit 1
}

. /data/adb/magisk/util_functions.sh

install_module
exit $?
'''

UPDATER = '#MAGISK\n'

with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("META-INF/com/google/android/update-binary", UPDATE_BINARY)
    z.writestr("META-INF/com/google/android/updater-script", UPDATER)

    for dirpath, dirs, files in os.walk(MOD):
        for fn in files:
            full = os.path.join(dirpath, fn)
            arc = os.path.relpath(full, MOD).replace("\\", "/")
            z.write(full, arc)

    if os.path.isdir(APPS):
        for fn in os.listdir(APPS):
            full = os.path.join(APPS, fn)
            if os.path.isfile(full):
                z.write(full, "apps/" + fn)

h = hashlib.sha256()
with open(OUT, "rb") as f:
    for c in iter(lambda: f.read(1 << 20), b""):
        h.update(c)
print("built:", OUT)
print("size :", os.path.getsize(OUT), "bytes")
print("sha256:", h.hexdigest())