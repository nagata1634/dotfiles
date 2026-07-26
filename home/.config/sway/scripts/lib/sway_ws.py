"""Sway ワークスペース共通ヘルパ。

奇数WS=右画面 / 偶数WS=左画面（15-workspace-outputs.conf の割当）を保つための
出力判定と切替をまとめる。ws-goto / ws-cycle / ws-pair から import して使う。

肝: 素の `workspace number N` は新規(空)WSを割当先ではなく「フォーカス中の出力」に
作ってしまう。そこで goto() は「対象パリティの画面を先に focus してから切替」し、
新規WSでも必ず 奇=右 / 偶=左 の正しい出力へ載せる。
"""
import json
import subprocess


def _workspaces():
    """swaymsg get_workspaces の結果（list[dict]）。"""
    return json.loads(subprocess.check_output(["swaymsg", "-t", "get_workspaces"]))


def _swaymsg(cmd):
    subprocess.run(["swaymsg", cmd], stdout=subprocess.DEVNULL)


def focused_num(default=0):
    """フォーカス中WSの番号。無ければ default。"""
    return next((w["num"] for w in _workspaces() if w["focused"]), default)


def visible_pair():
    """可視WSの (奇, 偶) を返す。無ければ (1, 2)。"""
    odd = even = 0
    for w in _workspaces():
        if w.get("visible") and 1 <= w["num"] <= 10:
            if w["num"] % 2:
                odd = w["num"]
            else:
                even = w["num"]
    return (odd or 1, even or 2)


def output_for(n):
    """番号 n を載せるべき出力名を返す。

    同パリティの可視WSが出ている出力（=その番号帯が物理的に出る画面）を優先。
    無ければフォーカス中の出力、それも無ければ任意の可視出力、どれも無ければ ""。
    出力名や左右の物理配置には依存しない（トグルで左右が入れ替わっても正しい）。
    """
    parity = n % 2
    vis = [w for w in _workspaces() if w.get("visible")]
    same = [w for w in vis if 1 <= w["num"] <= 10 and w["num"] % 2 == parity]
    if same:
        return same[0]["output"]
    foc = [w for w in vis if w["focused"]]
    if foc:
        return foc[0]["output"]
    return vis[0]["output"] if vis else ""


def goto(n):
    """WS n へ、正しい出力に載せてから切替（新規WSでも 奇=右/偶=左 を保証）。

    eDP-1 のみ（外部未接続）時は可視WSが1枚だけ＝focus先がその1画面になり、
    そのまま直接切替になる。
    """
    if not (1 <= n <= 10):
        return
    out = output_for(n)
    if out:
        _swaymsg(f"focus output {out}; workspace number {n}")
    else:
        _swaymsg(f"workspace number {n}")


def wrap(n, delta):
    """番号 n を同パリティ内で delta ステップ循環（奇:1..9 / 偶:2..10）。"""
    base = 1 if n % 2 else 2
    idx = (n - base) // 2                # 0..4
    idx = (idx + delta) % 5              # ±1 循環（Python の % は負でも 0..4）
    return base + idx * 2
