#!/usr/bin/env python3
"""ワークスペース循環切替（next/prev）。実切替は lib/sway_ws.goto に委譲。

  ws-cycle.py single next|prev
      フォーカス中の画面だけを同パリティ ±2 循環（右:1→3→5→7→9 / 左:2→4→6→8→10）。
  ws-cycle.py both   next|prev
      両画面それぞれを ±2（右=奇 / 左=偶 を各々進める）。例 (1,2)→(3,4)→(5,6)…

goto() が「対象パリティの画面を先に focus→切替」するので、both で両画面が片側に
寄る不具合や、逆パリティが画面に居座る不具合が起きない。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import sway_ws


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: ws-cycle.py single|both next|prev")
    scope, direction = sys.argv[1], sys.argv[2]
    delta = {"next": 1, "prev": -1}.get(direction)
    if delta is None:
        sys.exit("dir must be next|prev")

    if scope == "single":
        cur = sway_ws.focused_num()
        if 1 <= cur <= 10:
            sway_ws.goto(sway_ws.wrap(cur, delta))
    elif scope == "both":
        odd, even = sway_ws.visible_pair()
        # 右(奇)→左(偶)の順に切替。最後に左へフォーカスが残る（従来挙動）。
        sway_ws.goto(sway_ws.wrap(odd, delta))
        sway_ws.goto(sway_ws.wrap(even, delta))
    else:
        sys.exit("scope must be single|both")


if __name__ == "__main__":
    main()
