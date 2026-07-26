#!/usr/bin/env python3
"""ワークスペース一覧をrofiで選んで切り替える。一覧にない名前を入力すれば新規作成。"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import rofi


def main():
    wss = json.loads(subprocess.check_output(["swaymsg", "-t", "get_workspaces"]))
    names = [w["name"] for w in wss]
    sel = rofi.dmenu(names, prompt="Workspace")
    if not sel:
        return
    subprocess.run(["swaymsg", "workspace", sel])


if __name__ == "__main__":
    main()
