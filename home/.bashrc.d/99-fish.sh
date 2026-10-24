# 対話シェルだけ fish に切り替える。ログインシェルは bash のまま（plasmalogin の wayland-session は
# bash --login で ~/.bash_profile → ~/.bashrc → ~/.bashrc.d を読んで環境を作るので、そこは変えない）。
# ~/.bashrc.d の最後に置くので、EDITOR などはここまでで設定済みのまま fish に引き継がれる。
#   - fish の中で `bash` と打つと本物の bash（SHLVL が 2 になり、ここを通らない）。ヒアドキュメント用
#   - NO_FISH=1 bash でも bash のまま
#   - fish が無ければ何もしない
if [[ $- == *i* ]] && [ "$SHLVL" = 1 ] && [ -z "${NO_FISH:-}" ] && command -v fish >/dev/null \
   && [ "$(ps -o comm= -p "$PPID")" != fish ]; then
    if shopt -q login_shell; then exec fish --login; else exec fish; fi
fi
