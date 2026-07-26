"""rofi dmenu 共通ヘルパ。テーマは ~/.config/rofi/config.rasi 固定。

メニュー系スクリプト（power-menu / notif-center / scratchpad-menu / settings-menu）
から import して使い、rofi 呼び出しの定型（-dmenu -i -theme …）を一元化する。
"""
import os
import subprocess

THEME = os.path.expanduser("~/.config/rofi/config.rasi")


def dmenu(items, prompt=None, no_custom=False, password=False, lines=None,
          index=False, extra=None):
    """items を rofi dmenu にかけ、選択を返す。

    items は list[str] か改行区切り str。各行に row() のメタ（latin 絞り込み用）を
    埋めてもよい。
      no_custom : 一覧外入力を禁止
      password  : 伏字入力
      lines     : 表示行数
      index     : True なら選択行の 0始まり index(int) を返す（未選択は None）。
                  False なら選択された表示文字列を返す（未選択は ""）。
      extra     : rofi へ追加で渡す引数の list（例 ["-show-icons", "-theme-str", …]）
    """
    cmd = ["rofi", "-dmenu", "-i", "-theme", THEME]
    if prompt is not None:
        cmd += ["-p", prompt]
    if no_custom:
        cmd.append("-no-custom")
    if password:
        cmd.append("-password")
    if lines is not None:
        cmd += ["-lines", str(lines)]
    if index:
        cmd += ["-format", "i"]
    if extra:
        cmd += list(extra)
    text = items if isinstance(items, str) else "\n".join(items)
    p = subprocess.run(cmd, input=text, capture_output=True, text=True)
    out = p.stdout.strip()
    if index:
        return int(out) if out != "" else None
    return out


def row(label, meta):
    """latin 絞り込み用メタ付きの1行を作る。

    rofi dmenu の行オプション形式 `<表示>\\0meta\\x1f<検索語>`。
    日本語が打てなくても英字/ローマ字（meta）で絞り込め、戻り値は表示ラベル。
    """
    return f"{label}\0meta\x1f{meta}"


def confirm(prompt):
    """「はい/いいえ」の2択を出し、「はい」なら True。"""
    ans = dmenu(
        [row("いいえ", "no iie cancel"), row("はい", "yes hai ok")],
        prompt=prompt, no_custom=True, lines=2,
    )
    return ans == "はい"
