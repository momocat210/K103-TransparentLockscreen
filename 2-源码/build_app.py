#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建并签名「猫猫透明锁屏forAlita」控制端 APP（WebView + smali root 桥）。

本机内存紧张时 apktool/aapt2 回编译会 bad_alloc。
控制逻辑（smali / dex）未变、只更新 assets/index.html 时，
直接从已签名的基线 APK 替换页面并重新签名，结果与回编译等价且省内存。
若基线 APK 缺失，则回退到完整 apktool 回编译。
"""
import glob
import hashlib
import os
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(ROOT, "app")
BUILD = os.path.join(ROOT, "_appbuild")
TOOLS = os.path.join("C:/Users/slien/WorkBuddy/2026-11-06-20-20-23", "inkos", "tools")
APKTOOL = os.path.join(TOOLS, "apktool.jar")
SIGNER = os.path.join(TOOLS, "uber-apk-signer.jar")
BASE = os.path.join(ROOT, "猫猫透明锁屏forAlita-v1.1.apk")
OUT = os.path.join(ROOT, "猫猫透明锁屏forAlita-v1.2.apk")
JAVA = ("C:/Users/slien/.workbuddy/binaries/python/versions/3.13.12/"
        "Lib/site-packages/jdk4py/java-runtime/bin/java.exe")


def sh(args):
    print("  $ " + " ".join('"%s"' % a if " " in a else a for a in args))
    r = subprocess.run(args, capture_output=True, text=True, errors="replace")
    if r.stdout.strip():
        print(r.stdout.strip()[-2500:])
    if r.returncode != 0:
        print(r.stderr.strip()[-2500:])
        raise RuntimeError("命令失败 rc=%d" % r.returncode)
    return r


def make_unsigned(unsigned):
    html_path = os.path.join(APP, "assets", "index.html")
    # 空间充足时优先完整 apktool 回编译；内存不足(aapt2 bad_alloc)时回退到基线替换。
    try:
        print("=== 1/3 apktool 完整回编译 ===")
        sh([JAVA, "-Xmx512m", "-jar", APKTOOL, "b", APP, "-o", unsigned])
        return
    except Exception as e:
        print("  回编译失败(%s)，回退到基线替换页面" % e)
    if not os.path.exists(BASE):
        raise RuntimeError("回编译失败且无基线 APK 可用")
    print("=== 1/3 从基线 APK 替换页面（省内存路径）===")
    html = open(html_path, "rb").read()
    with zipfile.ZipFile(BASE) as zin, zipfile.ZipFile(unsigned, "w") as zout:
        for item in zin.infolist():
            data = html if item.filename == "assets/index.html" else zin.read(item.filename)
            zout.writestr(item, data)
    print("  基线: %s / 页面 %d B" % (os.path.basename(BASE), len(html)))


def build():
    if not os.path.exists(APP) or not os.path.exists(SIGNER) or not os.path.exists(JAVA):
        raise RuntimeError("缺少构建依赖")
    if os.path.isdir(BUILD):
        shutil.rmtree(BUILD)
    os.makedirs(BUILD)
    signed_dir = os.path.join(BUILD, "signed")
    os.makedirs(signed_dir)

    unsigned = os.path.join(BUILD, "unsigned.apk")
    make_unsigned(unsigned)

    print("=== 2/3 签名 + zipalign ===")
    sh([JAVA, "-Xmx256m", "-jar", SIGNER, "-a", unsigned, "-o", signed_dir, "--allowResign"])
    apks = sorted(glob.glob(os.path.join(signed_dir, "*-aligned-debugSigned.apk")))
    if not apks:
        raise RuntimeError("签名产物未生成: " + repr(os.listdir(signed_dir)))
    shutil.copy2(apks[0], OUT)

    print("=== 3/3 校验 ===")
    with zipfile.ZipFile(OUT) as z:
        names = set(z.namelist())
        needed = {"AndroidManifest.xml", "classes.dex", "resources.arsc",
                  "assets/index.html"}
        missing = needed - names
        if missing:
            raise RuntimeError("APK 缺少: " + ", ".join(sorted(missing)))
        signed = [n for n in names if n.startswith("META-INF/") and
                  n.endswith((".RSA", ".SF", ".MF"))]
        if not signed:
            raise RuntimeError("APK 未包含 v1 签名文件")
        dex = z.read("classes.dex")
        html = z.read("assets/index.html").decode("utf-8")
        if b"MainActivity" not in dex or b"CmdTask" not in dex:
            raise RuntimeError("classes.dex 缺少预期的类")
        if b"a5pro" in dex or b"btpage" in dex:
            raise RuntimeError("classes.dex 残留旧包名")
        if b"k103/lockscreen" not in dex:
            raise RuntimeError("classes.dex 未使用新包名 k103")
        for key in ("setconf(", "showGallery", "SHUFFLE", "TRACK_EVERY", "trackRow",
                    "K103_Lockscreen", "猫猫透明锁屏", "待显示"):
            if key not in html:
                raise RuntimeError("index.html 缺少 " + key)
        print("  PASS  classes.dex %d B / index.html %d B / %d 签名文件"
              % (len(dex), len(html.encode("utf-8")), len(signed)))

    h = hashlib.sha256(open(OUT, "rb").read()).hexdigest()
    print("\nAPK : %s" % OUT)
    print("大小: %d bytes" % os.path.getsize(OUT))
    print("SHA256: %s" % h)
    print("包名: com.momocat.k103.lockscreen / 名称: 猫猫透明锁屏forAlita")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(build())
    except Exception as e:
        print("BUILD FAILED: %s" % e)
        sys.exit(1)