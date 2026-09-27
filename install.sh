#!/usr/bin/env bash
# dotfiles — Fedora Kinoite (KDE Plasma) の環境をこのマシンに再現する。冪等。
#
#   curl -fsSL https://raw.githubusercontent.com/nagata1634/dotfiles/main/install.sh | bash
#
# 理由は CLAUDE.md を参照。
set -euo pipefail

REPO="https://github.com/nagata1634/dotfiles.git"
DIR="$HOME/.dotfiles"
TS="$(date +%Y%m%d-%H%M%S)"

# ~/.config 配下でディレクトリごとリンクするもの
LINK_DIRS=(fcitx5 environment.d)
# ファイル単位でリンクするもの（~/.bashrc.d や systemd/user は環境固有のファイルと同居するため）
LINK_FILES=(
  .profile
  .bashrc
  .bashrc.d/60-editor.sh
  .bashrc.d/90-tty-locale.sh
  .vscode/argv.json
  .config/kde-scripts/lid-unlock-output-fix.sh
  .config/kde-scripts/panel-sensors.js
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
  .var/app/md.obsidian.Obsidian/config/fontconfig/fonts.conf
)
ENABLE_UNITS=(ssh-agent.socket kde-lid-unlock-fix.service monitoralign.service qnap-tpbk.service)

# "<GitHub repo>|<KPackage type>|<id>|<asset の末尾>|<導入後に実行する package 内スクリプト>"
KDE_PACKAGES=(
  "nagata1634/kwin-monitoralign|KWin/Script|monitoralign|.kwinscript|contents/install-daemon.sh"
  "nagata1634/plasma-spanimage|Plasma/Wallpaper|dev.yuya.spanimage|.wallpaper.zip|"
  "anametologin/krohnkite|KWin/Script|krohnkite|.kwinscript|"
)
THEME_REPOS=(vinceliuice/WhiteSur-kde vinceliuice/WhiteSur-icon-theme)

latest_asset() {  # $1=repo $2=asset の末尾 → ダウンロード URL
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | grep -oE '"browser_download_url": *"[^"]+'"$2"'"' | head -1 | cut -d'"' -f4
}

# 1. リポジトリ
if [ -d "$DIR/.git" ]; then git -C "$DIR" pull --ff-only; else git clone "$REPO" "$DIR"; fi

# 2. rpm-ostree レイヤ（intel-media-driver は RPM Fusion が先に要る）
mapfile -t pkgs < <(sed 's/#.*//' "$DIR/packages.txt" | xargs -n1)
rpm-ostree install --idempotent --allow-inactive "${pkgs[@]}"

# 3. シンボリックリンク（既存の実体は .bak.<日時> に退避）
link() {
  local src="$DIR/home/$1" dst="$HOME/$1"
  [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ] && return 0
  mkdir -p "$(dirname "$dst")"
  { [ -e "$dst" ] || [ -L "$dst" ]; } && mv "$dst" "$dst.bak.$TS"
  ln -sfn "$src" "$dst"
}
for d in "${LINK_DIRS[@]}"; do link ".config/$d"; done
for f in "${LINK_FILES[@]}"; do link "$f"; done

# plasmalogin は bash --login で起動し、bash は ~/.bash_profile があると ~/.profile を読まないので読ませる
grep -qF '. "$HOME/.profile"' ~/.bash_profile 2>/dev/null \
  || printf '\n[ -r "$HOME/.profile" ] && . "$HOME/.profile"\n' >> ~/.bash_profile

# 4. docker-compose（podman compose の provider）
url="$(latest_asset docker/compose docker-compose-linux-x86_64)"
mkdir -p ~/.local/bin && curl -fsSL "$url" -o ~/.local/bin/docker-compose && chmod +x ~/.local/bin/docker-compose

# 5. Flatpak
flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sed 's/#.*//' "$DIR/flatpaks.txt" | xargs -r flatpak install -y --or-update --system --noninteractive flathub

# 6. KDE 拡張（KDE Store と同じ GitHub Releases のアーカイブ）
for spec in "${KDE_PACKAGES[@]}"; do
  IFS='|' read -r repo type id suffix post <<<"$spec"
  tmp="$(mktemp -d)"; curl -fsSL "$(latest_asset "$repo" "$suffix")" -o "$tmp/pkg$suffix"
  kpackagetool6 -t "$type" -u "$tmp/pkg$suffix" 2>/dev/null || kpackagetool6 -t "$type" -i "$tmp/pkg$suffix"
  rm -rf "$tmp"
  if [ -n "$post" ]; then "$(kpackagetool6 -t "$type" -s "$id" | sed -n 's/^Path *: *//p')/$post"; fi
done

# 7. テーマ（WhiteSur の Aurorae 装飾とアイコン。kde-snapshot が参照する）
for repo in "${THEME_REPOS[@]}"; do
  src="$HOME/.cache/dotfiles-src/${repo##*/}"
  [ -d "$src" ] || git clone -q --depth 1 "https://github.com/$repo.git" "$src"
  case "$repo" in
    */WhiteSur-kde)        (cd "$src" && ./install.sh) ;;
    */WhiteSur-icon-theme) (cd "$src" && ./install.sh -d "$HOME/.local/share/icons") ;;
  esac
done

# 8. authselect（Yubikey → 指紋 → パスワード）
authselect current 2>/dev/null | grep -q custom/yuya-auth \
  || pkexec sh -c "mkdir -p /etc/authselect/custom/yuya-auth && cp '$DIR'/system/authselect/yuya-auth/* /etc/authselect/custom/yuya-auth/ && authselect select custom/yuya-auth with-pam-u2f with-fingerprint with-mdns4 with-silent-lastlog --force"

# 9. systemd --user
systemctl --user daemon-reload
systemctl --user enable "${ENABLE_UNITS[@]}"

cat <<'EOF'

完了。初回だけ手動で:
  kde-snapshot restore                                   # KDE 設定を復元 → ログアウト/ログイン
  mkdir -p ~/.config/Yubico && pamu2fcfg > ~/.config/Yubico/u2f_keys
  system/ の usb-wakeup は CLAUDE.md の手順で pkexec 配置
  データは Pika Backup（NAS）から復元
EOF
