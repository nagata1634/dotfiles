# EDITOR / VISUAL。/etc/profile.d/nano-default-editor.sh が立てる EDITOR=nano を上書きする。
#
# ここに置く理由: Fedora の /etc/bashrc は非ログインシェルに対して /etc/profile.d/* を
# 読み直すため、~/.profile に書いても端末では nano に戻される。~/.bashrc.d は
# その後に読まれるので、ここが唯一勝てる場所であり宣言箇所を1つに保てる。
# 詳細は ~/.dotfiles/CLAUDE.md の「セッションと環境変数」を参照。
export EDITOR=nvim

# VISUAL は GUI セッションのときだけ。素の TTY で VSCode は起動できず、
# 復旧作業中に git や sudoedit がエディタを開けなくなる。
[ -n "${WAYLAND_DISPLAY:-}" ] && export VISUAL='code --wait'
