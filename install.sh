#!/usr/bin/env bash
# dotfiles — Fedora Sway Atomic の環境をこのマシンに再現する。
#
#   1) dotfiles を ~/.dotfiles に clone / pull
#   2) packages.txt を rpm-ostree でレイヤリング（不足分のみ）
#   3) fonts.txt の Nerd Font を ~/.local/share/fonts へ導入
#   4) home/ 配下を ~/ にシンボリックリンク（既存実体はタイムスタンプ付きで退避）
#   5) ~/.bash_profile に ~/.profile の読み込みブロックを冪等に挿入
#   6) 保全系 systemd --user ユニットを有効化
#
# 冪等。再実行しても安全。curl | bash でも動く。
#
#   curl -fsSL https://raw.githubusercontent.com/nagata1634/dotfiles/main/install.sh | bash
#
# オプション:
#   --minimal         自作スクリプト群(config.ext.d / scripts)をリンクしない（素の Sway 構成）
#   --skip-packages   rpm-ostree のレイヤリングを行わない
#   --skip-fonts      フォント導入を行わない
#
# 設計の背景は同リポジトリの CLAUDE.md を参照。
set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/nagata1634/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
NERD_FONTS_REPO="ryanoasis/nerd-fonts"
TS="$(date +%Y%m%d-%H%M%S)"

MINIMAL=0
SKIP_PACKAGES=0
SKIP_FONTS=0
for arg in "$@"; do
  case "$arg" in
    --minimal)       MINIMAL=1 ;;
    --skip-packages) SKIP_PACKAGES=1 ;;
    --skip-fonts)    SKIP_FONTS=1 ;;
    -h|--help)       sed -n '2,19p' "${BASH_SOURCE[0]}" 2>/dev/null | sed 's/^# \?//'; exit 0 ;;
    *) printf '不明なオプション: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

# ~/.config 配下でディレクトリごとリンクするもの
LINK_DIRS=(sway rofi waybar dunst foot fcitx5 environment.d)
# 個別ファイルでリンクするもの（リポジトリ内 home/ からの相対パス = ~/ からの相対パス）
LINK_FILES=(
  # GUI セッションの環境の起点。plasmalogin の wayland-session が bash --login 経由で読む（greetd 時代と同じ経路）。
  ".profile"
  ".config/locale.env"
  ".config/systemd/user/waybar.service"
  ".config/systemd/user/swayidle.service"
  # アイドル・離席・ログアウトの連鎖（ロック画面は持たない）
  ".config/systemd/user/sway-idle-blank.service"
  ".config/systemd/user/sway-idle-resume.service"
  ".config/systemd/user/sway-away-mark.service"
  ".config/systemd/user/sway-away-check.service"
  ".config/systemd/user/sway-sleep-prepare.service"
  ".config/systemd/user/sway-lid-logout.service"
  ".config/systemd/user/sway-logout.service"
  # ログイン後に Magic Trackpad の入力を入れ直す（環境固有だが害は無いので含める）
  ".config/systemd/user/sway-trackpad-reset.service"
  # 蓋を閉じた状態でアンロックすると内蔵ディスプレイが復活する
  # kscreenlockerの不具合対策（bugs.kde.org #363238 等と同系統）。
  ".config/kde-scripts/lid-unlock-output-fix.sh"
  # DP-8 パネルの System Monitor Sensor 4つ(Disks/メモリ/CPU/ネットワーク)を Plasma の
  # scripting API で設定するスクリプト(手動実行。applet id は環境固有、ファイル冒頭参照)。
  ".config/kde-scripts/panel-sensors.js"
  ".config/systemd/user/kde-lid-unlock-fix.service"
  # Solarized の配色と、それを使うグローバルテーマ（日の出/日の入り連動切替の対象）。
  ".local/share/color-schemes/SolarizedLight.colors"
  ".local/share/color-schemes/SolarizedDark.colors"
  ".local/share/plasma/look-and-feel/dev.yuya.solarized.light"
  ".local/share/plasma/look-and-feel/dev.yuya.solarized.dark"
  # ※ Monitor Align(KWin スクリプト)と Span Image(壁紙プラグイン)は独立リポジトリ。
  #   EXTERNAL_REPOS で clone し、各リポジトリの install.sh --link で導入する。
  ".bashrc"
  ".bashrc.d/50-aliases.sh"
  ".bashrc.d/60-editor.sh"
  ".bashrc.d/90-tty-locale.sh"
  ".vscode/argv.json"
  ".claude/skills/system-audit"
)
# ~/.bashrc.d/ はディレクトリごとリンクしない。環境固有のスクリプト
# （bitwarden.sh など）が消えるため、ファイル単位で扱う。
# ~/.claude/skills/ も同じ理由でスキル単位（プラグイン由来のスキルが同居するため）。
# 有効化する systemd --user ユニット（常駐のみ。sway-* の oneshot は start されるだけ）
ENABLE_UNITS=(waybar.service swayidle.service sway-trackpad-reset.service ssh-agent.socket kde-lid-unlock-fix.service)

# 自作の KDE 拡張で、独立リポジトリとして公開しているもの（~/Documents に clone、--link で導入）
EXTERNAL_REPOS=(nagata1634/kwin-monitoralign nagata1634/plasma-spanimage)

PROFILE_BEGIN="# >>> dotfiles: profile >>>"
PROFILE_END="# <<< dotfiles: profile <<<"
# 旧構成のマーカー。ロケールと ssh-agent を ~/.bash_profile に直書きしていた頃のもので、
# 中身は ~/.profile に移設済み。見つけたら撤去する。
LEGACY_BLOCKS=("dotfiles: GUI locale" "dotfiles: ssh-agent")

c_info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m✓\033[0m %s\n'  "$*"; }
c_warn() { printf '\033[1;33m!\033[0m %s\n'  "$*"; }
die()    { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

NEED_REBOOT=0

# ----- 0. 前提チェック --------------------------------------------------
check_prereq() {
  command -v git   >/dev/null 2>&1 || die "git が必要です。"
  command -v curl  >/dev/null 2>&1 || die "curl が必要です。"
  if [ "$SKIP_FONTS" -eq 0 ]; then
    command -v unzip >/dev/null 2>&1 || die "unzip が必要です（--skip-fonts で回避できます）。"
  fi
  if [ "$SKIP_PACKAGES" -eq 0 ]; then
    command -v rpm-ostree >/dev/null 2>&1 \
      || die "rpm-ostree が見つかりません。Fedora Atomic 系専用です（--skip-packages で回避できます）。"
    # intel-media-driver は RPM Fusion(free) 由来。未導入だとレイヤリングが失敗するので先に案内する。
    if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
      c_warn "RPM Fusion (free) が未導入です。intel-media-driver のレイヤリングが失敗する場合は先に:"
      c_warn "  rpm-ostree install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm"
    fi
  fi
}

# curl | bash では stdin が pipe なので sudo がパスワードを読めない。
# /dev/tty から読ませて事前に認証しておく。
ensure_sudo() {
  sudo -n true 2>/dev/null && return 0
  [ -e /dev/tty ] || die "端末が無いため管理者権限を取得できません。--skip-packages を付けるか、スクリプトを保存して実行してください。"
  c_info "パッケージのレイヤリングに管理者権限が必要です"
  sudo -v < /dev/tty || die "認証に失敗しました。"
}

# ----- 1. リポジトリ ----------------------------------------------------
# packages.txt / fonts.txt はリポジトリ内にあるため、必ず clone を先に済ませる
# （curl | bash では $BASH_SOURCE が使えず、スクリプトと同階層のファイルを読めない）。
sync_repo() {
  if [ -d "$DOTFILES_DIR/.git" ]; then
    c_info "dotfiles を更新: $DOTFILES_DIR"
    git -C "$DOTFILES_DIR" pull --ff-only || c_warn "pull に失敗しました（ローカルの変更を確認してください）"
  else
    c_info "dotfiles を clone: $DOTFILES_REPO → $DOTFILES_DIR"
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  fi
  [ -d "$DOTFILES_DIR/home" ] || die "$DOTFILES_DIR/home が見つかりません。リポジトリの構造を確認してください。"
}

# ----- 2. パッケージのレイヤリング（不足分のみ）-------------------------
layer_packages() {
  local list="$DOTFILES_DIR/packages.txt"
  [ -f "$list" ] || { c_warn "packages.txt が無いためスキップ"; return 0; }

  local installed
  installed="$(rpm-ostree status --booted --json 2>/dev/null \
    | python3 -c 'import sys,json; print(" ".join(json.load(sys.stdin)["deployments"][0].get("requested-packages",[])))')" \
    || die "rpm-ostree の状態を取得できません。"

  local want=() pkg
  while read -r pkg; do
    pkg="${pkg%%#*}"; pkg="${pkg//[[:space:]]/}"
    [ -z "$pkg" ] && continue
    if [[ " $installed " == *" $pkg "* ]]; then
      c_ok "既にレイヤリング済み: $pkg"
    else
      want+=("$pkg")
    fi
  done < "$list"

  if [ ${#want[@]} -eq 0 ]; then
    c_ok "追加レイヤリングは不要です。"
    return 0
  fi

  c_info "レイヤリングします: ${want[*]}"
  ensure_sudo
  sudo rpm-ostree install --idempotent "${want[@]}"
  NEED_REBOOT=1
}

# ----- 3. フォント ------------------------------------------------------
install_fonts() {
  local list="$DOTFILES_DIR/fonts.txt"
  [ -f "$list" ] || { c_warn "fonts.txt が無いためスキップ"; return 0; }

  local destroot="$HOME/.local/share/fonts"
  mkdir -p "$destroot"
  local changed=0 line name tag dest url tmp

  while read -r line; do
    line="${line%%#*}"
    # shellcheck disable=SC2086
    set -- $line
    name="${1:-}"; tag="${2:-latest}"
    [ -z "$name" ] && continue

    dest="$destroot/${name}Nerd"
    if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
      c_ok "フォント導入済み: $name"
      continue
    fi

    if [ "$tag" = "latest" ]; then
      tag="$(curl -fsSL "https://api.github.com/repos/$NERD_FONTS_REPO/releases/latest" \
             | grep -m1 '"tag_name"' | cut -d'"' -f4)" || tag=""
      [ -n "$tag" ] || die "$name: 最新タグを取得できません。fonts.txt にタグを直接書いてください。"
      c_info "$name: 最新タグ $tag を使用"
    fi

    url="https://github.com/$NERD_FONTS_REPO/releases/download/$tag/${name}.zip"
    tmp="$(mktemp -d)"
    c_info "フォントを取得: $name ($tag)"
    if ! curl -fsSL "$url" -o "$tmp/font.zip"; then
      rm -rf "$tmp"; die "取得に失敗しました: $url"
    fi
    mkdir -p "$dest"
    unzip -qo "$tmp/font.zip" -d "$dest" -x 'LICENSE*' 'README*' 'OFL*' || { rm -rf "$tmp"; die "展開に失敗しました: $name"; }
    rm -rf "$tmp"
    changed=1
    c_ok "フォント導入: $name → $dest"
  done < "$list"

  if [ "$changed" -eq 1 ]; then
    fc-cache -f "$destroot" >/dev/null 2>&1 || c_warn "fc-cache に失敗しました（手動で実行してください）"
    c_ok "フォントキャッシュを更新しました"
  fi
}

# ----- 3b. docker-compose（podman compose の provider）-------------------
# podman-compose のレイヤを外し、公式の静的バイナリを ~/.local/bin に置く。
# `podman compose` は PATH の docker-compose を provider として使う。VS Code の
# dev.containers.dockerComposePath は GUI の PATH に ~/.local/bin が無いため絶対パスで指定する。
COMPOSE_REPO="docker/compose"
install_compose() {
  local dest="$HOME/.local/bin/docker-compose" tag url tmp
  mkdir -p "$HOME/.local/bin"
  tag="$(curl -fsSL "https://api.github.com/repos/$COMPOSE_REPO/releases/latest" \
         | grep -m1 '"tag_name"' | cut -d'"' -f4)" || tag=""
  [ -n "$tag" ] || { c_warn "docker-compose: 最新タグを取得できません（スキップ）"; return 0; }
  if [ -x "$dest" ] && "$dest" version --short 2>/dev/null | grep -qx "${tag#v}"; then
    c_ok "docker-compose 導入済み: $tag"
    return 0
  fi
  url="https://github.com/$COMPOSE_REPO/releases/download/$tag/docker-compose-linux-x86_64"
  tmp="$(mktemp -d)"
  c_info "docker-compose を取得: $tag"
  curl -fsSL "$url" -o "$tmp/docker-compose" && curl -fsSL "$url.sha256" -o "$tmp/sum" \
    || { rm -rf "$tmp"; c_warn "docker-compose の取得に失敗しました（スキップ）"; return 0; }
  ( cd "$tmp" && sed 's# .*# docker-compose#' sum | sha256sum -c --quiet ) \
    || { rm -rf "$tmp"; die "docker-compose: sha256 が一致しません"; }
  install -m 0755 "$tmp/docker-compose" "$dest"
  rm -rf "$tmp"
  c_ok "docker-compose 導入: $tag → $dest"
}

# ----- 4. シンボリックリンク --------------------------------------------
# $1 = リポジトリ内 home/ 以下のパス, $2 = $HOME 以下のパス
link_one() {
  local src="$DOTFILES_DIR/home/$1" dst="$HOME/$2"
  [ -e "$src" ] || { c_warn "リポジトリに無いためスキップ: $1"; return 0; }

  if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
    c_ok "リンク済み: ~/$2"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    mv "$dst" "${dst}.bak.${TS}"
    c_warn "既存を退避: ~/$2 → $(basename "$dst").bak.${TS}"
  fi
  ln -sfn "$src" "$dst"
  c_ok "リンク: ~/$2 → $src"
}

deploy() {
  local d f
  for d in "${LINK_DIRS[@]}"; do
    if [ "$d" = "sway" ] && [ "$MINIMAL" -eq 1 ]; then
      # 素の Sway 構成: 拡張(config.ext.d)と自作スクリプト(scripts)を除いてリンクする。
      # config 末尾の layered-include はマッチしないパスを黙って無視するので警告も出ない。
      link_one ".config/sway/config"   ".config/sway/config"
      link_one ".config/sway/config.d" ".config/sway/config.d"
      link_one ".config/sway/assets"   ".config/sway/assets"
      c_warn "--minimal: config.ext.d と scripts はリンクしません（素の Sway 構成）"
      continue
    fi
    link_one ".config/$d" ".config/$d"
  done
  for f in "${LINK_FILES[@]}"; do
    link_one "$f" "$f"
  done

  # スクリプトの実行ビットを保証（bindsym から直接呼ぶため）
  if [ -d "$DOTFILES_DIR/home/.config/sway/scripts" ]; then
    find "$DOTFILES_DIR/home/.config/sway/scripts" -type f \( -name '*.sh' -o -name '*.py' \) \
      -exec chmod +x {} + 2>/dev/null || true
  fi
}

# ----- 5. ~/.bash_profile から ~/.profile を読ませる ---------------------
# GUI セッションの環境（ロケール・ssh-agent）の実体は ~/.profile にある。DM（plasmalogin）が
#   [ -f /etc/profile ] && . /etc/profile; [ -f $HOME/.profile ] && . $HOME/.profile; exec sway
# を実行するためで、~/.bash_profile は GUI セッションでは読まれない。
# 一方 bash のログインシェルは ~/.bash_profile があると ~/.profile を読まないので、
# symlink できないこのファイルにだけマーカーで読み込み行を挿入する。
install_bash_profile_block() {
  local f="$HOME/.bash_profile" name
  touch "$f"

  # 旧構成（ロケールと ssh-agent を直書きしていた2ブロック）の撤去。
  for name in "${LEGACY_BLOCKS[@]}"; do
    grep -qF "# >>> $name >>>" "$f" || continue
    [ -e "$f.bak.$TS" ] || cp -a "$f" "$f.bak.$TS"
    sed -i "/^# >>> $name >>>\$/,/^# <<< $name <<<\$/d" "$f"
    c_ok "~/.bash_profile の旧ブロックを撤去しました: $name"
  done

  if grep -qF "$PROFILE_BEGIN" "$f"; then
    c_ok "~/.bash_profile の ~/.profile 読み込みブロックは既に存在します"
    return 0
  fi
  cat >> "$f" <<EOF

$PROFILE_BEGIN
# bash のログインシェルは ~/.bash_profile があると ~/.profile を読まないため明示的に読む。
# ロケールと ssh-agent の実体は ~/.profile 側（DM が GUI セッションで読むのはそちら）。
# ~/.bashrc の後に置くこと: TTY では .bashrc 側が先に LC_ALL を立て、
# ~/.profile のガードがそれを尊重して英語のまま保つ。
# 詳細は ~/.dotfiles/CLAUDE.md の「GUI セッションの環境（~/.profile）」を参照。
[ -r "\$HOME/.profile" ] && . "\$HOME/.profile"
$PROFILE_END
EOF
  c_ok "~/.bash_profile に ~/.profile の読み込みを追加しました"
}

# ----- 5b. 独立リポジトリの KDE 拡張 -------------------------------------
install_external_repos() {
  command -v kpackagetool6 >/dev/null 2>&1 || { c_warn "KDE 環境ではないため独立リポジトリの導入をスキップ"; return 0; }
  local repo dir
  for repo in "${EXTERNAL_REPOS[@]}"; do
    dir="$HOME/Documents/${repo##*/}"
    if [ -d "$dir/.git" ]; then
      git -C "$dir" pull -q --ff-only 2>/dev/null || c_warn "$repo: pull できませんでした（ローカル変更あり？）"
    else
      git clone -q "https://github.com/$repo.git" "$dir" || { c_warn "$repo: clone に失敗"; continue; }
    fi
    if "$dir/install.sh" --link >/dev/null; then c_ok "導入: $repo (--link)"; else c_warn "$repo: install.sh --link が失敗"; fi
  done
}

# ----- 6. systemd --user ユニット ---------------------------------------
enable_units() {
  command -v systemctl >/dev/null 2>&1 || { c_warn "systemctl が無いためスキップ"; return 0; }
  local u
  for u in "${ENABLE_UNITS[@]}"; do
    if [ -z "$(systemctl --user list-unit-files "$u" --no-legend 2>/dev/null)" ]; then
      c_warn "ユニットが見つからないためスキップ: $u"
      continue
    fi
    if systemctl --user enable "$u" >/dev/null 2>&1; then
      c_ok "有効化: $u"
    else
      c_warn "有効化できませんでした: $u"
    fi
  done
}

# ----- 実行 -------------------------------------------------------------
check_prereq
c_info "=== 1/5 リポジトリ ==="; sync_repo
if [ "$SKIP_PACKAGES" -eq 0 ]; then c_info "=== 2/5 パッケージ ==="; layer_packages
else c_warn "=== 2/5 パッケージ === スキップ"; fi
if [ "$SKIP_FONTS" -eq 0 ]; then c_info "=== 3/5 フォント ==="; install_fonts
else c_warn "=== 3/5 フォント === スキップ"; fi
install_compose
c_info "=== 4/5 設定の配置 ==="; deploy; install_bash_profile_block
c_info "=== 5/5 サービス ==="; enable_units; install_external_repos

echo
c_ok "セットアップ完了。"
echo
c_info "次の手順:"
echo "  • 壁紙を ~/Pictures/background/ に配置（sway/config と config.d/10-outputs.conf 参照）"
echo "  • ロケールの配線を確認:  locale-audit"
echo "  • Gmail / カレンダーの PWA 常駐は環境固有のため別途セットアップ（README 参照）"
if [ "$NEED_REBOOT" -eq 1 ]; then
  echo "  • パッケージを反映するため再起動:  systemctl reboot"
else
  echo "  • ログインし直すか Sway を再読み込み:  swaymsg reload"
fi
