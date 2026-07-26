#!/usr/bin/env python3
"""スクラッチパッド内のウィンドウを rofi で選んで表示する（FIFO巡回の代替）。

各項目に app_id からジャンルアイコン(Nerd Font)を付けて表示。
"""
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import rofi


def icon_for(app):
    """app_id/class → ジャンルアイコン（Nerd Font, AdwaitaMono Nerd Font 前提）。"""
    a = app.lower()

    def has(*subs):
        return any(s in a for s in subs)

    if has("mail", "gmail"):
        return "󰇮"
    if has("calendar"):
        return "󰃭"
    if has("obsidian", "note", "logseq"):
        return "󰠮"
    if has("bitwarden", "pass", "keepass", "vault"):
        return "󰌾"
    if has("brave", "chrom", "firefox", "web", "browser"):
        return "󰖟"
    if has("term", "foot", "wezterm", "kitty", "alacritty"):
        return ""
    if has("code", "editor", "vim"):
        return "󰨞"
    if has("spotify", "lollypop", "music", "player"):
        return "󰎆"
    if has("files", "nautilus", "nemo", "thunar"):
        return "󰉋"
    if has("podman", "docker", "container"):
        return "󰡨"
    return "󰖯"


def scratch_windows():
    """スクラッチパッド(__i3_scratch)の floating ウィンドウ (id, app, title) リスト。"""
    tree = json.loads(subprocess.check_output(["swaymsg", "-t", "get_tree"]))
    scratch = None

    def find(node):
        nonlocal scratch
        if scratch is not None:
            return
        if node.get("name") == "__i3_scratch":
            scratch = node
            return
        for c in node.get("nodes", []) + node.get("floating_nodes", []):
            find(c)

    find(tree)
    if not scratch:
        return []
    out = []
    for n in scratch.get("floating_nodes", []):
        app = n.get("app_id") or (n.get("window_properties") or {}).get("class") or "app"
        title = n.get("name") or "(無題)"
        out.append((n["id"], app, title))
    return out


def main():
    wins = scratch_windows()
    if not wins:
        if shutil.which("notify-send"):
            subprocess.run(["notify-send", "スクラッチパッド", "ウィンドウがありません"])
        return

    id_by_label = {}
    labels = []
    for wid, app, title in wins:
        label = f"{icon_for(app)}  {app}  —  {title}"
        labels.append(label)
        id_by_label[label] = wid

    sel = rofi.dmenu(labels, prompt="Scratchpad")
    if not sel:
        return
    wid = id_by_label.get(sel)
    if wid is not None:
        subprocess.run(["swaymsg", f"[con_id={wid}] scratchpad show"],
                       stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
