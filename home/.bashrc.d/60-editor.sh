# EDITOR / VISUAL（/etc/profile.d/nano-default-editor.sh を上書き。~/.bashrc.d は最後に読まれるのでここに置く）
export EDITOR=nvim
# VISUAL は GUI のときだけ（素の TTY では code が起動できない）
[ -n "${WAYLAND_DISPLAY:-}" ] && export VISUAL='code --wait'
