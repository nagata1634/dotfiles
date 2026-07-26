#!/usr/bin/env python3
"""画面の明るさ調整。内蔵パネル=brightnessctl / 外部モニタ(DP)=ddcutil(DDC/CI)。

  brightness.py up   [STEP]   # STEP% 上げる（既定 5）
  brightness.py down [STEP]   # STEP% 下げる
  brightness.py set  N        # N% に設定
  brightness.py get           # 現在値(%)（内蔵優先、無ければ外部の1台）

対象は swaymsg get_outputs の active な出力で決める:
  内蔵(eDP*/LVDS*/DSI*) が active → brightnessctl（カーネル backlight）
  外部が active                  → ddcutil で全外部モニタを DDC/CI 調整
  両方 active なら両方。→ どの構成でも「見えている画面」の明るさが変わる。

外部モニタは backlight を持たない（brightnessctl の管轄外）。ddcutil 未導入や
モニタ側 DDC/CI 無効の場合は、その旨を通知して内蔵のみ処理する。
"""
import json
import shutil
import subprocess
import sys

VCP_BRIGHTNESS = "10"   # DDC/CI VCP feature 0x10 = Brightness


def active_outputs():
    try:
        outs = json.loads(subprocess.check_output(["swaymsg", "-t", "get_outputs"]))
    except Exception:
        return []
    return [o["name"] for o in outs if o.get("active")]


def is_internal(name):
    return name.startswith(("eDP", "LVDS", "DSI"))


def notify(msg, value=None):
    if not shutil.which("notify-send"):
        return
    cmd = ["notify-send", "-e",
           "-h", "string:x-canonical-private-synchronous:brightness", "-t", "800"]
    if value is not None:
        cmd += ["-h", f"int:value:{value}"]
    cmd.append(msg)
    subprocess.run(cmd)


# ---- 内蔵 (brightnessctl) ----
def bctl_get():
    try:
        out = subprocess.check_output(["brightnessctl", "-m"], text=True)
        return int(out.split(",")[3].rstrip("%"))
    except Exception:
        return None


def bctl_set(spec):
    subprocess.run(["brightnessctl", "-q", "set", spec])


# ---- 外部 (ddcutil) ----
def ddc_displays():
    """ddcutil の Display 番号リスト（DDC/CI 対応で検出できたもの）。"""
    if not shutil.which("ddcutil"):
        return []
    try:
        out = subprocess.check_output(["ddcutil", "detect", "--brief"],
                                      text=True, stderr=subprocess.DEVNULL, timeout=20)
    except Exception:
        return []
    return [ln.split()[-1] for ln in out.splitlines() if ln.startswith("Display ")]


def ddc_get(disp):
    try:
        out = subprocess.check_output(
            ["ddcutil", "--display", disp, "getvcp", VCP_BRIGHTNESS, "--brief"],
            text=True, stderr=subprocess.DEVNULL, timeout=15)
        parts = out.split()          # "VCP 10 C <cur> <max>"
        if "C" in parts:
            return int(parts[parts.index("C") + 1])
    except Exception:
        pass
    return None


def ddc_set(disp, spec):
    # spec は絶対 "N" か相対 "+ N" / "- N"（ddcutil setvcp の相対指定）
    subprocess.run(["ddcutil", "--display", disp, "setvcp", VCP_BRIGHTNESS] + spec.split(),
                   stderr=subprocess.DEVNULL)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: brightness.py up|down|set|get [ARG]")
    action = sys.argv[1]
    arg = sys.argv[2] if len(sys.argv) > 2 else None

    outs = active_outputs()
    internal = [o for o in outs if is_internal(o)]
    external = [o for o in outs if not is_internal(o)]

    if action == "get":
        v = bctl_get() if internal else None
        if v is None and external:
            disps = ddc_displays()
            if disps:
                v = ddc_get(disps[0])
        print(v if v is not None else "")
        return

    step = int(arg) if (action in ("up", "down") and arg) else 5

    # 内蔵
    if internal:
        if action == "up":
            bctl_set(f"{step}%+")
        elif action == "down":
            bctl_set(f"{step}%-")
        elif action == "set" and arg is not None:
            bctl_set(f"{int(arg)}%")

    # 外部
    if external:
        if not shutil.which("ddcutil"):
            notify("外部モニタの明るさには ddcutil が必要です（未導入・要インストール＆再起動）")
        else:
            disps = ddc_displays()
            if not disps:
                notify("外部モニタ: DDC/CI 対応ディスプレイ無し（モニタOSDで DDC/CI を有効に）")
            for d in disps:
                if action == "up":
                    ddc_set(d, f"+ {step}")
                elif action == "down":
                    ddc_set(d, f"- {step}")
                elif action == "set" and arg is not None:
                    ddc_set(d, f"{int(arg)}")

    # 通知（内蔵があれば実値バー付き、外部のみなら簡易）
    if internal:
        v = bctl_get()
        if v is not None:
            notify(f"Brightness: {v}%", v)
    elif external and shutil.which("ddcutil"):
        notify("外部モニタの明るさを調整")


if __name__ == "__main__":
    main()
