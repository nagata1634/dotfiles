#!/usr/bin/env python3
"""Mod+数字 でのワークスペース切替（絶対マッピング + フォーカス追従）。

  ws-goto.py <N>        N=1..10（0キーは 10 を渡す）

キー番号 N = WS番号。奇数キー→右画面 / 偶数キー→左画面、押した画面へフォーカスも
移動する（左画面で奇数キー→右画面へ切替）。実処理は lib/sway_ws.goto に委譲。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import sway_ws


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: ws-goto.py <1..10>")
    sway_ws.goto(int(sys.argv[1]))


if __name__ == "__main__":
    main()
