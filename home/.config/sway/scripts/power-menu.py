#!/usr/bin/env python3
"""Rofi 電源メニュー（Nord 統一テーマ）。

Waybar の電源アイコンクリック、または $mod+x から起動。
破壊的な操作（再起動/シャットダウン/更新/ログアウト/BIOS）は「はい/いいえ」確認を
はさむ。更新系は端末を開いて進捗を表示する。
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import rofi

# ユーザーの端末（$term と同じ foot ラッパー）。`start --` は term.sh 側で吸収される。
TERM = os.path.expanduser("~/.config/sway/scripts/term.sh")


def run_in_term(cmd):
    """更新系を端末で実行して進捗を見せる。"""
    subprocess.run([TERM, "start", "--", "bash", "-lc", cmd])


def notify(title, body):
    subprocess.run(["notify-send", title, body])


def booted_origin():
    """現在 boot している ostree の origin ref（例 fedora:fedora/44/x86_64/sericea）。"""
    try:
        out = subprocess.check_output(
            ["rpm-ostree", "status", "--booted", "--json"], stderr=subprocess.DEVNULL)
        return json.loads(out)["deployments"][0]["origin"]
    except Exception:
        return ""


def upgrade_next_version():
    """現在より新しい最小バージョンへ rebase（variant 改名にも追従）。"""
    EXTRA_VARIANTS = []   # 例: ["sway-atomic"]。将来の改名に備えるなら追記。
    origin = booted_origin()
    remote = origin.split(":", 1)[0] if ":" in origin else origin
    m_ver = re.search(r".*/([0-9]+)/[^/]+/[^/]+$", origin)
    m_arch = re.search(r".*/[0-9]+/([^/]+)/[^/]+$", origin)
    m_var = re.search(r".*/([^/]+)$", origin)
    ver = m_ver.group(1) if m_ver else ""
    arch = m_arch.group(1) if m_arch else ""
    cur_variant = m_var.group(1) if m_var else ""

    variant_id = ""
    try:
        for line in open("/etc/os-release"):
            if line.startswith("VARIANT_ID="):
                variant_id = line.split("=", 1)[1].strip().strip('"')
    except Exception:
        pass

    if not (origin and ver and arch and cur_variant):
        notify("OSアップグレード", f"現在の ref を判別できませんでした（{origin}）。")
        return

    # variant 候補（優先順・重複除去・空除去）:
    #   1) 現在の variant  2) /etc/os-release の VARIANT_ID  3) EXTRA_VARIANTS
    cands = []
    for c in [cur_variant, variant_id, *EXTRA_VARIANTS]:
        if c and c not in cands:
            cands.append(c)
    alt = "|".join(cands)

    notify("OSアップグレード", "新しいバージョンを確認しています…")
    try:
        raw = subprocess.check_output(
            ["ostree", "remote", "refs", remote],
            stderr=subprocess.DEVNULL, timeout=25, text=True)
    except Exception:
        raw = ""

    # updates/testing/rawhide を除くベース ref のみを (ver, variant) で取得
    pat = re.compile(rf"^{re.escape(remote)}:fedora/([0-9]+)/{re.escape(arch)}/({alt})$")
    refs = []
    for line in raw.splitlines():
        m = pat.match(line.strip())
        if m:
            refs.append((m.group(1), m.group(2)))

    newer = sorted({int(v) for v, _ in refs if int(v) > int(ver)})
    if not newer:
        notify("OSアップグレード", f"{ver} より新しいバージョンはまだ提供されていません。")
        return
    nxt = str(newer[0])

    # その版で実在する variant を優先順に採用（rename 検知）
    chosen_variant = ""
    for c in cands:
        if (nxt, c) in refs:
            chosen_variant = c
            break
    next_ref = f"{remote}:fedora/{nxt}/{arch}/{chosen_variant}"

    msg = f"Fedora {ver} → {nxt} にアップグレード（rebase）して再起動しますか？"
    if chosen_variant != cur_variant:
        msg += f"\n※variant が {cur_variant} → {chosen_variant} に変わります"
    if rofi.confirm(f"{msg}\n({next_ref})"):
        run_in_term(f"rpm-ostree rebase {next_ref} && systemctl reboot")


def main():
    rows = [
        rofi.row("󰌾  ロック", "lock screen rokku"),
        rofi.row("󰒲  サスペンド", "suspend sleep sasupendo"),
        rofi.row("󰍃  ログアウト", "logout exit logoff roguauto"),
        rofi.row("󰜉  再起動", "reboot restart saikidou"),
        rofi.row("󰐥  シャットダウン", "shutdown poweroff shutdown shatto"),
        rofi.row("󰚰  OS更新して再起動", "os update upgrade koushin"),
        rofi.row("󰏖  フル更新して再起動", "full update upgrade flatpak furu koushin"),
        rofi.row("󰬬  次バージョンへアップグレード", "rebase next version upgrade tsugi version"),
        rofi.row("󰒓  BIOS設定で再起動", "bios firmware setup uefi"),
    ]
    choice = rofi.dmenu(rows, prompt="電源", no_custom=True)
    if not choice:
        return

    # 判定順は重要（"OS更新して再起動" 等が "再起動" を含むため、再起動は最後に）
    if "ロック" in choice:
        subprocess.run(["gtklock", "-d"])
    elif "サスペンド" in choice:
        subprocess.run(["systemctl", "suspend"])
    elif "ログアウト" in choice:
        if rofi.confirm("ログアウトしますか？"):
            subprocess.run(["swaymsg", "exit"])
    elif "シャットダウン" in choice:
        if rofi.confirm("シャットダウンしますか？"):
            subprocess.run(["systemctl", "poweroff"])
    elif "BIOS" in choice:
        if rofi.confirm("BIOS設定で再起動しますか？"):
            subprocess.run(["systemctl", "reboot", "--firmware-setup"])
    elif "OS更新" in choice:
        if rofi.confirm("OSを更新して再起動しますか？"):
            run_in_term("rpm-ostree upgrade && systemctl reboot")
    elif "フル更新" in choice:
        if rofi.confirm("OSとアプリを更新して再起動しますか？"):
            run_in_term("rpm-ostree upgrade; flatpak update -y; systemctl reboot")
    elif "次バージョン" in choice:
        upgrade_next_version()
    elif "再起動" in choice:
        if rofi.confirm("再起動しますか？"):
            subprocess.run(["systemctl", "reboot"])


if __name__ == "__main__":
    main()
