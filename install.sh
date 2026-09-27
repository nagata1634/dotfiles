#!/usr/bin/env bash
# dotfiles — ~/ の層だけを入れる。冪等。OS・アプリ・/etc は pxe-boot の Kickstart が担当。
#
#   curl -fsSL https://raw.githubusercontent.com/nagata1634/dotfiles/main/install.sh | bash
set -euo pipefail

DIR="$HOME/.dotfiles"
TS="$(date +%Y%m%d-%H%M%S)"

# ~/.config 配下でディレクトリごとリンクするもの
LINK_DIRS=(fcitx5 environment.d)
# ファイル単位でリンクするもの（~/.bashrc.d や systemd/user は環境固有のファイルと同居するため）
LINK_FILES=(
  .bashrc.d/60-editor.sh
  .bashrc.d/90-tty-locale.sh
  .vscode/argv.json
  .config/kde-scripts/lid-unlock-output-fix.sh
  .config/systemd/user/kde-lid-unlock-fix.service
  .config/systemd/user/qnap-tpbk.service
  .local/bin/kde-snapshot
  .local/share/color-schemes/SolarizedLight.colors
  .local/share/color-schemes/SolarizedDark.colors
  .local/share/plasma/look-and-feel/dev.yuya.solarized.light
  .local/share/plasma/look-and-feel/dev.yuya.solarized.dark
  .local/share/flatpak/overrides/global
  .local/share/flatpak/overrides/com.brave.Browser
  .local/share/flatpak/overrides/com.bitwarden.desktop
)
ENABLE_UNITS=(ssh-agent.socket kde-lid-unlock-fix.service monitoralign.service qnap-tpbk.service)

# "<GitHub repo>|<KPackage type>|<id>|<asset の末尾>|<導入後に実行する package 内スクリプト>"
KDE_PACKAGES=(
  "nagata1634/kwin-monitoralign|KWin/Script|monitoralign|.kwinscript|contents/install-daemon.sh"
  "nagata1634/plasma-spanimage|Plasma/Wallpaper|dev.yuya.spanimage|.wallpaper.zip|"
  "anametologin/krohnkite|KWin/Script|krohnkite|.kwinscript|"
)

# 1. リポジトリ
if [ -d "$DIR/.git" ]; then git -C "$DIR" pull --ff-only
else git clone https://github.com/nagata1634/dotfiles.git "$DIR"; fi

# 2. シンボリックリンク（既存の実体は .bak.<日時> に退避）
link() {
  local src="$DIR/home/$1" dst="$HOME/$1"
  [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ] && return 0
  mkdir -p "$(dirname "$dst")"
  { [ -e "$dst" ] || [ -L "$dst" ]; } && mv "$dst" "$dst.bak.$TS"
  ln -sfn "$src" "$dst"
}
for d in "${LINK_DIRS[@]}"; do link ".config/$d"; done
for f in "${LINK_FILES[@]}"; do link "$f"; done

# 3. KDE 拡張（KDE Store と同じ GitHub Releases のアーカイブ）
for spec in "${KDE_PACKAGES[@]}"; do
  IFS='|' read -r repo type id suffix post <<<"$spec"
  url="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | grep -oE '"browser_download_url": *"[^"]+'"$suffix"'"' | head -1 | cut -d'"' -f4)"
  tmp="$(mktemp -d)"; curl -fsSL "$url" -o "$tmp/pkg$suffix"
  kpackagetool6 -t "$type" -u "$tmp/pkg$suffix" 2>/dev/null || kpackagetool6 -t "$type" -i "$tmp/pkg$suffix"
  rm -rf "$tmp"
  if [ -n "$post" ]; then "$(kpackagetool6 -t "$type" -s "$id" | sed -n 's/^Path *: *//p')/$post"; fi
done

# 4. ウィンドウ装飾（kwinrc が Aurorae の WhiteSur-dark を参照する）
src="$HOME/.cache/dotfiles-src/WhiteSur-kde"
[ -d "$src" ] || git clone -q --depth 1 https://github.com/vinceliuice/WhiteSur-kde.git "$src"
(cd "$src" && ./install.sh)

# 5. systemd --user
systemctl --user daemon-reload
systemctl --user enable "${ENABLE_UNITS[@]}"

cat <<'EOF'

完了。初回だけ手動で:
  kde-snapshot restore        # KDE 設定と Pika Backup の設定を復元 → ログアウト/ログイン
  mkdir -p ~/.config/Yubico && pamu2fcfg > ~/.config/Yubico/u2f_keys
  データは Pika Backup（NAS）から復元
EOF
