#!/usr/bin/env python3
"""起動時、リテラル名 "number N" (num=-1) で作られてしまった初期ワークスペースを
正しい番号ワークスペース "N" へリネームする保険スクリプト。

背景:
  sway 起動時、`workspace number N output ...`（15-workspace-outputs.conf）の割当から
  各出力の初期ワークスペースが作られる際、名前が "number N" になり num=-1 となって
  $mod+数字（= workspace number N）で選べなくなる現象が起きることがある。
  （$mod+数字や `swaymsg workspace 8` 自体は正常に num 付きWSを作れるので、
   問題は「起動時に作られた初期WSの名前」だけ）。

  そこで起動直後に "number <n>" という名前のWSを "<n>" にリネームし、num=<n> に正す。
  通常運用時（既に "1"/"2" 等）は該当が無く no-op なので、reload で呼ばれても無害。
"""
import json
import re
import subprocess
import time

# 初期WSの生成と競合しないよう少し待つ
time.sleep(1)

wss = json.loads(subprocess.check_output(["swaymsg", "-t", "get_workspaces"]))
for w in wss:
    m = re.fullmatch(r"number (\d+)", w["name"])
    if m:
        subprocess.run(["swaymsg", f'rename workspace "{w["name"]}" to {m.group(1)}'])
