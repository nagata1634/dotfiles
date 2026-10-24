# 対話用の fish。ログインシェルは bash のままで、~/.bashrc.d/99-fish.sh が対話時だけ ここに切り替える。
# 環境変数は bash 側（~/.bashrc.d）で設定済みのものを引き継ぐので、ここでは書かない。
if status is-interactive
    set -g fish_greeting   # 起動時のあいさつを出さない

    # fzf: Ctrl+R 履歴 / Ctrl+T ファイル / Alt+C ディレクトリ
    if command -q fzf
        fzf --fish | source
    end
end
