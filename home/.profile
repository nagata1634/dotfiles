# GUI(sway)セッションの環境。ここが sway 配下の全 GUI アプリの環境の起点になる。
#
# greetd はセッションを次のコマンドで起動する（バイナリに埋め込まれている）:
#   [ -f /etc/profile ] && . /etc/profile; [ -f $HOME/.profile ] && . $HOME/.profile; exec sway
# つまり読まれるのは ~/.profile であって ~/.bash_profile ではない。
# sh で読まれるので POSIX 記法のみ（[[ ]]・配列・local は使えない）。
# 詳細は ~/.dotfiles/CLAUDE.md の「GUI セッションの環境（~/.profile）」を参照。

# ロケール。/etc/profile.d/lang.sh が CJK ロケールを en_US へ置換した後にあたるので
# ここで上書きする。TTY では ~/.bashrc.d/90-tty-locale.sh が先に LC_ALL を立てるため
# このガードでスキップされ、TTY は英語のまま保たれる。
if [ -z "${LC_ALL:-}" ] && [ -r "$HOME/.config/locale.env" ]; then
    set -a
    . "$HOME/.config/locale.env"
    set +a
fi

# ssh-agent のソケット。値の単一の真実の源は environment.d/10-ssh-agent.conf
# （systemd --user 側が読む同じファイル）。二重定義しない。
# これが無いと sway から起動した VS Code が SSH_AUTH_SOCK を持たず、
# devcontainer への転送も起きない。
if [ -r "$HOME/.config/environment.d/10-ssh-agent.conf" ]; then
    set -a
    . "$HOME/.config/environment.d/10-ssh-agent.conf"
    set +a
fi
