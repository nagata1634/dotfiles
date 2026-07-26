#!/usr/bin/env python3
"""両画面まとめてワークスペースを切り替える（ペア切替, $mod+Ctrl+数字）。

  ws-pair.py <N>    N → 右=奇数(2N-1) / 左=偶数(2N) を表示。

右→左の順に切替するので、最後に表示した左（調べ物側）にフォーカスが残る。
実切替は lib/sway_ws.goto に委譲（新規WSでも 奇=右/偶=左 の正しい出力へ載る）。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import sway_ws


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: ws-pair.py <pair-number>")
    n = int(sys.argv[1])
    sway_ws.goto(2 * n - 1)   # 右(奇)
    sway_ws.goto(2 * n)       # 左(偶, 最後にフォーカスが残る)


if __name__ == "__main__":
    main()
