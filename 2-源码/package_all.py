#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把源码 + 模块安装包 + APP + 文档 打成一个完整分发包（zip）。
排除：_analysis(反编译分析) / _appbuild(构建临时) / app/build(apktool中间产物) / 旧版本产物。
"""
import os
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
PKG_NAME = "K103_Lockscreen_完整包_v1.6"
PKG_DIR = os.path.join(ROOT, PKG_NAME)
OUT = os.path.join(ROOT, PKG_NAME + ".zip")

INSTALL = "1-模块安装包"
SOURCE = "2-源码"

# (源相对路径, 包内相对路径)
files = []

# ---- 文档 ----
files.append(("移植说明.md", "移植说明.md"))

# ---- 模块安装包 ----
files.append(("K103-TransparentLockscreen-v1.6.zip", f"{INSTALL}/K103-TransparentLockscreen-v1.6.zip"))
files.append(("猫猫透明锁屏forAlita-v1.2.apk", f"{INSTALL}/猫猫透明锁屏forAlita-v1.2.apk"))

# ---- 构建脚本 ----
for f in ("build_app.py", "build_zip.py", "package_all.py"):
    files.append((f, f"{SOURCE}/{f}"))

# ---- native：C源码 + stb头文件 + 已编译arm64二进制 ----
for f in ("img2raw_k103.c", "compose_k103.c", "framecmp_k103.c",
          "stb_image.h", "stb_image_write.h",
          "img2raw_k103", "compose_k103", "framecmp_k103"):
    files.append((f"native/{f}", f"{SOURCE}/native/{f}"))

# ---- module：全部部署文件（脚本/配置/tools/二进制/白底raw）----
for f in ("service.sh", "customize.sh", "uninstall.sh", "action.sh", "module.prop",
          "config.conf", "settings.conf", "settings.default.conf", "enabled", "README.txt",
          "img2raw_k103", "compose_k103", "framecmp_k103", "frame_white.raw"):
    files.append((f"module/{f}", f"{SOURCE}/module/{f}"))
files.append(("module/tools/lockscreen_ctl.sh", f"{SOURCE}/module/tools/lockscreen_ctl.sh"))

# ---- app：源码（排除 build/ 中间产物）----
for f in ("AndroidManifest.xml", "apktool.yml", "assets/index.html", "res/values/strings.xml"):
    files.append((f"app/{f}", f"{SOURCE}/app/{f}"))
for smali in ("CmdClient.smali", "CmdTask.smali", "MainActivity.smali"):
    files.append((f"app/smali/com/momocat/k103/lockscreen/{smali}",
                  f"{SOURCE}/app/smali/com/momocat/k103/lockscreen/{smali}"))


def main():
    for rel in files:
        src = os.path.join(ROOT, rel[0])
        if not os.path.isfile(src):
            raise SystemExit("缺少源文件: " + rel[0])
    for _, dst in files:
        os.makedirs(os.path.dirname(os.path.join(PKG_DIR, dst)), exist_ok=True)
    for src, dst in files:
        data = open(os.path.join(ROOT, src), "rb").read()
        open(os.path.join(PKG_DIR, dst), "wb").write(data)
    readme = open(os.path.join(ROOT, "README-先看我.txt"), "rb").read()
    open(os.path.join(PKG_DIR, "README-先看我.txt"), "wb").write(readme)

    if os.path.exists(OUT):
        os.remove(OUT)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for base, dirs, names in os.walk(PKG_DIR):
            dirs.sort()
            for n in sorted(names):
                p = os.path.join(base, n)
                z.write(p, os.path.relpath(p, ROOT).replace("\\", "/"))
    print("OK ->", OUT, os.path.getsize(OUT), "bytes,", len(files) + 1, "files")


if __name__ == "__main__":
    main()