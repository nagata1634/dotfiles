#!/usr/bin/env python3
"""Sway の全キーバインドを rofi で「キー → 機能名」で一覧表示し、選んだものを実行する。

- 設定テキストの取得:
    `swaymsg -t get_config` は **メイン config しか返さず、`include`（config.d）を
    展開しない**。そのため config.d 側のバインド（スクラッチパッド F キーや
    ワークスペースペア切替など）が一覧から抜けてしまう。
    そこで Sway 本体の layered-include と同じ規則で config.d/*.conf を自前で読み、
    メイン config に連結してから bindsym を抽出する。
- `set $mod ...` などの変数を解決して実際のキー表記にする
- 機能名（説明）は **設定ファイルのコメントから取得する**:
    バインドの直前行に `#: 機能名` と書くと、それが表示名になる。
    （i3/Sway は行末インラインコメントを許可しないため、説明は必ず「前の行」に書く）
  `#:` が無いバインドは生コマンドをそのまま表示する。
- rofi で選択するとそのコマンドを実行する。

用途: キーの組み合わせを忘れたときの早見表 兼、マウス操作派のランチャー。
"""
import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import rofi

# Sway 本体の include が参照する config.d 群（後にあるほど同名ファイルで優先）。
# config 末尾の layered-include と同じ順序・同じ「後勝ち」規則を再現する。
XDG = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
CONFIG_D_DIRS = [
    "/usr/share/sway/config.d",
    "/etc/sway/config.d",
    os.path.join(XDG, "sway", "config.d"),
    # 自作スクリプト依存の拡張。config 本体が config.d の後に include するので
    # ここでも最後に置く（同名ファイルがあれば後勝ちになる）。
    os.path.join(XDG, "sway", "config.ext.d"),
]

# 表示を読みやすくするキー名の置換（コマンド実行には影響しない）
PRETTY_KEYS = {"Mod4": "Super", "Mod1": "Alt", "Mod3": "Hyper",
               "Return": "Enter", "grave": "`", "minus": "-", "space": "Space",
               "slash": "/", "bracketleft": "[", "bracketright": "]"}


def collect_config_d() -> str:
    """layered-include と同じ規則で config.d/*.conf を集めて連結する。

    同名ファイルは後ろのディレクトリ（＝ユーザ ~/.config が最優先）で上書きし、
    最終的な集合を **ベース名のソート順**で読み込む（Sway の読み込み順に一致）。
    """
    chosen = {}  # basename -> path（後勝ち）
    for d in CONFIG_D_DIRS:
        for path in glob.glob(os.path.join(d, "*.conf")):
            chosen[os.path.basename(path)] = path
    parts = []
    for name in sorted(chosen):
        try:
            with open(chosen[name], encoding="utf-8") as f:
                parts.append(f.read())
        except OSError:
            pass
    return "\n".join(parts)


def get_config_text() -> str:
    # メイン config（get_config は include を展開しない）＋ config.d を自前連結。
    out = subprocess.run(
        ["swaymsg", "-t", "get_config"],
        capture_output=True, text=True, check=True,
    ).stdout
    main = json.loads(out)["config"]
    return main + "\n" + collect_config_d()


def parse_binds(text: str):
    variables = {}
    for m in re.finditer(r"^\s*set\s+(\$\w+)\s+(.+?)\s*$", text, re.M):
        variables[m.group(1)] = m.group(2).strip()

    def resolve(s: str) -> str:
        for _ in range(5):  # 変数が変数を含む場合に備えて数回
            new = s
            for k, v in variables.items():
                new = new.replace(k, v)
            if new == s:
                break
            s = new
        return s

    def prettify(keys: str) -> str:
        return "+".join(PRETTY_KEYS.get(p, p) for p in keys.split("+"))

    binds = []          # (keys, command, desc)
    pending_desc = None  # 直前行の `#: 機能名`
    for raw in text.splitlines():
        s = raw.strip()

        cm = re.match(r"#:\s*(.+)$", s)  # 機能名コメント
        if cm:
            pending_desc = cm.group(1).strip()
            continue

        bm = re.match(r"bindsym\s+(.*)$", s)
        if bm:
            tokens = bm.group(1).split()
            i = 0
            while i < len(tokens) and tokens[i].startswith("--"):  # フラグ除去
                i += 1
            if i < len(tokens) and tokens[i + 1:]:
                keys = prettify(resolve(tokens[i]))
                command = resolve(" ".join(tokens[i + 1:]))
                desc = pending_desc or command  # コメントが無ければ生コマンド
                binds.append((keys, command, desc))
            pending_desc = None
            continue

        pending_desc = None  # 隣接していないコメントは無効化

    return binds


def main():
    binds = parse_binds(get_config_text())
    if not binds:
        sys.exit("bindsym が見つかりませんでした")

    width = max(len(k) for k, _, _ in binds)
    # 表示は「キー  機能名(日本語)」。日本語入力なしでも絞り込めるよう、
    # rofi の dmenu 行オプション meta に英字（キー＋生コマンド）を載せる。
    #   形式: <表示>\0meta\x1f<検索語>   （\0=NUL, \x1f=US）
    lines = []
    for keys, command, desc in binds:
        display = f"{keys.ljust(width)}   {desc}"
        meta = f"{keys} {command}".replace("\n", " ").replace("\0", " ")
        lines.append(f"{display}\0meta\x1f{meta}")

    idx = rofi.dmenu(lines, prompt="keybind", no_custom=True, index=True)
    if idx is None:
        return  # キャンセル

    _, command, _ = binds[idx]
    subprocess.run(["swaymsg", "--", command])


if __name__ == "__main__":
    main()
