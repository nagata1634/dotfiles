#!/usr/bin/env python3
"""Rofi 設定ハブ（Nord 統一テーマ）。

Mod+Ctrl+S で起動。ハブから各サブメニューへ降りる。
  引数なし        → ハブ
  引数(section名) → 各サブメニュー（「戻る」でハブへ）
ナビゲーションは os.execv で自身を再起動して実現（bash の `exec "$0" section` 相当）。
"""
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import rofi

SCRIPTS = os.path.expanduser("~/.config/sway/scripts")
BACK = "󰌍  戻る"
SELF = os.path.abspath(__file__)


def menu(items, prompt):
    """一覧外入力を禁止した rofi メニュー（bash の menu() 相当）。"""
    return rofi.dmenu(items, prompt=prompt, no_custom=True)


def notify(msg):
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "設定", msg])


def spawn(*cmd):
    """GUI 等をバックグラウンド起動（bash の `cmd &`）。"""
    subprocess.Popen(list(cmd), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def reopen(section=None):
    """自身を再起動（bash の `exec "$0" [section]`）。"""
    args = [sys.executable, SELF] + ([section] if section else [])
    sys.stdout.flush()
    os.execv(sys.executable, args)


def home():
    reopen()


def _out(cmd, **kw):
    """コマンド出力（文字列）。失敗時は ""。"""
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL, **kw)
    except Exception:
        return ""


# ---------- WiFi ----------
def section_wifi():
    if _out(["nmcli", "-t", "-f", "WIFI", "radio"]).strip() == "disabled":
        choice = menu(["󰖩  WiFi を有効にする", "󰒓  詳細設定 (nm-connection-editor)", BACK],
                      "WiFi: オフ")
        if "有効" in choice:
            subprocess.run(["nmcli", "radio", "wifi", "on"]); notify("WiFi を有効化")
        elif "詳細" in choice:
            spawn("nm-connection-editor")
        elif "戻る" in choice:
            home()
        return

    def sig(s):
        s = int(s or 0)
        return "󰤨" if s >= 80 else "󰤥" if s >= 55 else "󰤢" if s >= 30 else "󰤟"

    raw = _out(["nmcli", "--terse", "--fields", "IN-USE,SIGNAL,SECURITY,SSID",
                "device", "wifi", "list", "--rescan", "yes"])
    ssids, secs, lines = [], [], []
    for line in raw.splitlines():
        line = line.replace("\\:", "\x1f")          # エスケープされた : を退避
        parts = line.split(":", 3)
        if len(parts) < 4:
            continue
        inuse, signal, security, ssid = parts
        ssid = ssid.replace("\x1f", ":")
        if not ssid:
            continue
        mark = "󰸞 " if inuse == "*" else "  "
        lock = " 󰌾" if security and security != "--" else ""
        ssids.append(ssid); secs.append(security)
        lines.append(f"{sig(signal)} {mark}{ssid}{lock}")

    items = lines + ["󰑓  再スキャン", "󰖪  WiFi を無効にする",
                     "󰒓  詳細設定 (nm-connection-editor)", BACK]
    choice = menu(items, "WiFi 接続")
    if not choice:
        return
    if "再スキャン" in choice:
        reopen("wifi")
    if "無効" in choice:
        subprocess.run(["nmcli", "radio", "wifi", "off"]); notify("WiFi を無効化"); return
    if "詳細設定" in choice:
        spawn("nm-connection-editor"); return
    if choice == BACK:
        home()

    target = sec = ""
    for i, ln in enumerate(lines):
        if ln == choice:
            target, sec = ssids[i], secs[i]
            break
    if not target:
        return

    known = _out(["nmcli", "-t", "-f", "NAME", "connection", "show"]).splitlines()
    if target in known:
        ok = subprocess.run(["nmcli", "connection", "up", "id", target]).returncode == 0
        notify(f"{target} に接続" if ok else f"{target} 接続失敗")
    elif sec and sec != "--":
        pw = rofi.dmenu([], prompt=f"{target} のパスワード", password=True, lines=0)
        if not pw:
            return
        ok = subprocess.run(["nmcli", "device", "wifi", "connect", target,
                             "password", pw]).returncode == 0
        notify(f"{target} に接続" if ok else f"{target} 接続失敗（パスワード確認）")
    else:
        ok = subprocess.run(["nmcli", "device", "wifi", "connect", target]).returncode == 0
        notify(f"{target} に接続" if ok else f"{target} 接続失敗")


# ---------- Bluetooth ----------
def section_bt():
    powered = ""
    for ln in _out(["bluetoothctl", "show"]).splitlines():
        if "Powered:" in ln:
            powered = ln.split()[-1]
            break
    toggle = "󰂲  Bluetooth を OFF にする" if powered == "yes" else "󰂲  Bluetooth を ON にする"

    devlines, macs = [], []
    if powered == "yes":
        for ln in _out(["bluetoothctl", "devices", "Paired"]).splitlines():
            f = ln.split(None, 2)          # "Device <mac> <name>"
            if len(f) < 3:
                continue
            mac, name = f[1], f[2]
            connected = "Connected: yes" in _out(["bluetoothctl", "info", mac])
            m = "󰸞 " if connected else "  "
            macs.append(mac); devlines.append(f"󰂱 {m}{name}")

    items = [toggle] + devlines + ["󰂯  詳細設定 (Blueman)", BACK]
    choice = menu(items, "Bluetooth")
    if not choice:
        return
    if "ON" in choice:
        subprocess.run(["bluetoothctl", "power", "on"]); notify("Bluetooth ON"); reopen("bt")
    if "OFF" in choice:
        subprocess.run(["bluetoothctl", "power", "off"]); notify("Bluetooth OFF"); return
    if "Blueman" in choice:
        spawn("blueman-manager"); return
    if choice == BACK:
        home()
    for i, ln in enumerate(devlines):
        if ln == choice:
            mac = macs[i]
            if "Connected: yes" in _out(["bluetoothctl", "info", mac]):
                subprocess.run(["bluetoothctl", "disconnect", mac]); notify("切断しました")
            else:
                ok = subprocess.run(["bluetoothctl", "connect", mac]).returncode == 0
                notify("接続しました" if ok else "接続失敗")
            break


# ---------- サウンド ----------
def section_sound():
    vg = _out(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
    m = re.search(r"([0-9.]+)", vg)
    vol = int(float(m.group(1)) * 100) if m else None
    muted = " 󰝟ミュート中" if "MUTED" in vg else ""

    # 出力一覧（id / name / 説明）。pactl はロケール依存なので LC_ALL=C で英語固定。
    env = dict(os.environ, LC_ALL="C")
    sinks = []
    sid = name = None
    for ln in _out(["pactl", "list", "sinks"], env=env).splitlines():
        if ln.startswith("Sink #"):
            sid = ln.split("#")[1].strip()
        elif ln.startswith("\tName: "):
            name = ln.split("Name:", 1)[1].strip()
        elif ln.startswith("\tDescription: "):
            desc = ln.split("Description:", 1)[1].strip()
            sinks.append((sid, name, desc))
    default = _out(["pactl", "get-default-sink"]).strip()

    sinklines, snames = [], []
    for sid, name, desc in sinks:
        mk = "󰸞 " if name == default else "  "
        snames.append(name); sinklines.append(f"󰓃 {mk}{desc}")

    items = ["󰝝  音量 +5%", "󰝞  音量 -5%", "󰝟  ミュート切替"] + sinklines + \
            ["󰍰  詳細 (pavucontrol)", BACK]
    choice = menu(items, f"サウンド  {vol if vol is not None else '?'}%{muted}")
    if not choice:
        return
    if "+5" in choice:
        subprocess.run(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", "5%+"]); reopen("sound")
    if "-5" in choice:
        subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"]); reopen("sound")
    if "ミュート切替" in choice:
        subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]); reopen("sound")
    if "pavucontrol" in choice:
        spawn("pavucontrol"); return
    if choice == BACK:
        home()
    for i, ln in enumerate(sinklines):
        if ln == choice:
            subprocess.run(["pactl", "set-default-sink", snames[i]]); notify("出力を切替"); reopen("sound")


# ---------- 画面の明るさ ----------
def section_bright():
    # 内蔵=brightnessctl / 外部=ddcutil を brightness.py が自動振り分け。
    bri = f"{SCRIPTS}/brightness.py"
    cur = _out([bri, "get"]).strip()
    choice = menu(["󰃠  +10%", "󰃞  -10%", "󰃟  25%", "󰃟  50%", "󰃟  75%", "󰃠  100%", BACK],
                  f"明るさ  現在 {(cur + '%') if cur else '?'}")
    if not choice:
        return
    if "+10" in choice:
        subprocess.run([bri, "up", "10"]); reopen("bright")
    if "-10" in choice:
        subprocess.run([bri, "down", "10"]); reopen("bright")
    for pct in ("25", "50", "75", "100"):
        if pct in choice:
            subprocess.run([bri, "set", pct]); reopen("bright")
    if choice == BACK:
        home()


# ---------- 壁紙 ----------
def section_wallpaper():
    choice = menu(["󰸉  壁紙を選ぶ（span / 内蔵は1枚）", "󰑓  現在の壁紙を再適用", BACK], "壁紙")
    if "選ぶ" in choice:
        subprocess.run([f"{SCRIPTS}/wallpaper-picker.py"])
    elif "再適用" in choice:
        subprocess.run([f"{SCRIPTS}/wallpaper-picker.py", "--reapply"]); notify("壁紙を再適用")
    elif choice == BACK:
        home()


# ---------- 境界（横モニタの縦位置 = 2画面の境目の高さ）----------
OUTCONF = os.path.expanduser("~/.config/sway/config.d/10-outputs.conf")
TOGGLE = f"{SCRIPTS}/toggle-monitors.py"


def landscape_output():
    """ライブの横モニタ名（外部・transform が 90/270 でない）。"""
    import json
    try:
        outs = json.loads(subprocess.check_output(["swaymsg", "-t", "get_outputs"]))
    except Exception:
        return ""
    for o in outs:
        if (o.get("active") and not o["name"].startswith(("eDP", "LVDS", "DSI"))
                and str(o.get("transform")) not in ("90", "270")):
            return o["name"]
    return ""


def set_boundary(y):
    """新しい Y に。静的設定2ファイルを更新→ライブ適用→壁紙再span。"""
    y = max(0, min(1120, int(y)))
    for f in (OUTCONF, TOGGLE):
        try:
            with open(f) as fh:
                txt = fh.read()
            txt = re.sub(r"position 0 [0-9]+", f"position 0 {y}", txt)
            with open(f, "w") as fh:
                fh.write(txt)
        except OSError:
            pass
    out = landscape_output()
    if out:
        subprocess.run(["swaymsg", "output", out, "position", "0", str(y)],
                       stdout=subprocess.DEVNULL)
    subprocess.run([f"{SCRIPTS}/wallpaper-picker.py", "--reapply"])
    notify(f"境界の高さ Y={y}")


def section_boundary():
    cur = 967
    m = re.search(r"position 0 ([0-9]+)", _out(["cat", OUTCONF]))
    if m:
        cur = int(m.group(1))
    choice = menu(["󰜸  上げる -50", "󰜸  上げる -10", "󰜶  下げる +10", "󰜶  下げる +50",
                   "󰉞  数値を入力", BACK],
                  f"境界の高さ  現在 Y={cur} (0〜1120)")
    if not choice:
        return
    if "上げる -50" in choice:
        set_boundary(cur - 50); reopen("boundary")
    if "上げる -10" in choice:
        set_boundary(cur - 10); reopen("boundary")
    if "下げる +10" in choice:
        set_boundary(cur + 10); reopen("boundary")
    if "下げる +50" in choice:
        set_boundary(cur + 50); reopen("boundary")
    if "数値" in choice:
        v = rofi.dmenu([], prompt="Y値 (0〜1120)", lines=0)
        if re.fullmatch(r"[0-9]+", v or ""):
            set_boundary(v)
        reopen("boundary")
    if choice == BACK:
        reopen("display")


# ---------- ディスプレイ ----------
def section_display():
    choice = menu(["󰍹  横/縦の配置を入れ替える", "󰕞  境界の高さを調整", "󰸉  壁紙を選ぶ", BACK],
                  "ディスプレイ")
    if "入れ替え" in choice:
        subprocess.run([TOGGLE]); notify("ディスプレイ配置を入替")
    elif "境界" in choice:
        reopen("boundary")
    elif "壁紙" in choice:
        reopen("wallpaper")
    elif choice == BACK:
        home()


# ---------- ナイトライト ----------
def section_night():
    on = subprocess.run(["pgrep", "-x", "wlsunset"], stdout=subprocess.DEVNULL).returncode == 0
    if on:
        choice = menu(["󰔏  ナイトライトを OFF", BACK], "ナイトライト: ON")
        if "OFF" in choice:
            subprocess.run(["pkill", "-x", "wlsunset"]); notify("ナイトライト OFF")
        elif choice == BACK:
            home()
    else:
        choice = menu(["󰔎  ナイトライトを ON（暖色）", BACK], "ナイトライト: OFF")
        if "ON" in choice:
            subprocess.Popen(["wlsunset", "-l", "35.7", "-L", "139.7", "-t", "3500", "-T", "6500"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
            notify("ナイトライト ON")
        elif choice == BACK:
            home()


# ---------- 電源プロファイル (tuned) ----------
def section_tuned():
    active = _out(["tuned-adm", "active"]).split(":")[-1].strip()
    profs = [ln.split()[1] for ln in _out(["tuned-adm", "list"]).splitlines()
             if ln.startswith("- ")]
    lines = [f"󰓅 {'󰸞 ' if p == active else '  '}{p}" for p in profs]
    choice = menu(lines + [BACK], f"電源プロファイル  現在: {active or '?'}")
    if not choice:
        return
    if choice == BACK:
        home()
    for i, ln in enumerate(lines):
        if ln == choice:
            ok = subprocess.run(["tuned-adm", "profile", profs[i]]).returncode == 0
            notify(f"プロファイル: {profs[i]}" if ok else "切替失敗（権限）")
            break


# ---------- 通知おやすみモード (dunst) ----------
def section_dnd():
    paused = _out(["dunstctl", "is-paused"]).strip()
    label = ("󰂜  おやすみモードを OFF（通知を再開）" if paused == "true"
             else "󰂚  おやすみモードを ON（通知を止める）")
    choice = menu([label, BACK], f"通知  {'停止中' if paused == 'true' else '通常'}")
    if "ON" in choice:
        subprocess.run(["dunstctl", "set-paused", "true"]); notify("おやすみモード ON")
    elif "OFF" in choice:
        subprocess.run(["dunstctl", "set-paused", "false"]); notify("通知を再開")
    elif choice == BACK:
        home()


# ---------- スクリーンショット ----------
def section_shot():
    import time
    choice = menu(["󰩭  範囲を保存", "󰆏  範囲をコピー", "󰹑  全画面を保存", "󰆏  全画面をコピー", BACK],
                  "スクリーンショット")
    if "範囲を保存" in choice:
        time.sleep(0.2); subprocess.run(["grimshot", "save", "area"]); notify("範囲を保存")
    elif "範囲をコピー" in choice:
        time.sleep(0.2); subprocess.run(["grimshot", "copy", "area"]); notify("範囲をコピー")
    elif "全画面を保存" in choice:
        subprocess.run(["grimshot", "save", "screen"]); notify("全画面を保存")
    elif "全画面をコピー" in choice:
        subprocess.run(["grimshot", "copy", "screen"]); notify("全画面をコピー")
    elif choice == BACK:
        home()


# ---------- ハブ ----------
def hub():
    items = ["󰖩  WiFi", "󰂯  Bluetooth", "󰕾  サウンド", "󰃞  画面の明るさ",
             "󰍹  ディスプレイ", "󰔎  ナイトライト", "󰓅  電源プロファイル",
             "󰂚  通知（おやすみモード）", "󰹑  スクリーンショット", "󰐥  電源"]
    choice = menu(items, "設定")
    dest = {
        "WiFi": "wifi", "Bluetooth": "bt", "サウンド": "sound", "明るさ": "bright",
        "ディスプレイ": "display", "ナイトライト": "night", "電源プロファイル": "tuned",
        "通知": "dnd", "スクリーンショット": "shot",
    }
    for key, section in dest.items():
        if key in choice:
            reopen(section)
    if "電源" in choice:
        os.execv(sys.executable, [sys.executable, f"{SCRIPTS}/power-menu.py"])


SECTIONS = {
    "wifi": section_wifi, "bt": section_bt, "sound": section_sound,
    "bright": section_bright, "display": section_display, "wallpaper": section_wallpaper,
    "boundary": section_boundary, "night": section_night, "tuned": section_tuned,
    "dnd": section_dnd, "shot": section_shot,
}


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    SECTIONS.get(arg, hub)()


if __name__ == "__main__":
    main()
