#!/usr/bin/env bash
# dotfiles — Fedora Sway Atomic の環境をこのマシンに再現する。
#
#   1) dotfiles を ~/.dotfiles に clone / pull
#   2) packages.txt を rpm-ostree でレイヤリング（不足分のみ）
#   3) fonts.txt の Nerd Font を ~/.local/share/fonts へ導入
#   4) home/ 配下を ~/ にシンボリックリンク（既存実体はタイムスタンプ付きで退避）
#   5) ~/.bash_profile にロケール読み込みブロックを冪等に挿入
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
  ".config/locale.env"
  ".config/systemd/user/waybar.service"
  ".config/systemd/user/swayidle.service"
  ".config/systemd/user/fcitx5-relock-watch.service"
  ".bashrc.d/90-tty-locale.sh"
  ".vscode/argv.json"
)
# 有効化する systemd --user ユニット（保全系のみ。PWA 常駐や NAS マウントは含めない）
ENABLE_UNITS=(waybar.service swayidle.service fcitx5-relock-watch.service ssh-agent.socket)

BLOCK_BEGIN="# >>> dotfiles: GUI locale >>>"
BLOCK_END="# <<< dotfiles: GUI locale <<<"

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

# ----- 5. ~/.bash_profile のロケールブロック ----------------------------
# symlink できない（既存ファイルへの追記になる）ため、マーカーで冪等に挿入する。
install_bash_profile_block() {
  local f="$HOME/.bash_profile"
  touch "$f"
  if grep -qF "$BLOCK_BEGIN" "$f"; then
    c_ok "~/.bash_profile のロケールブロックは既に存在します"
    return 0
  fi
  cat >> "$f" <<EOF

$BLOCK_BEGIN
# GUI(sway)セッション用ロケールを適用する。/etc/profile.d/lang.sh が VT 上のログイン
# シェルで LANG を en_US に置換するため、その後にあたるこの位置で上書きする。
# TTY では ~/.bashrc.d/90-tty-locale.sh が先に LC_ALL を立てるのでスキップされる。
# 詳細は ~/.dotfiles/CLAUDE.md の「ロケール分離」を参照。
if [ -z "\${LC_ALL:-}" ] && [ -r "\$HOME/.config/locale.env" ]; then
    set -a
    . "\$HOME/.config/locale.env"
    set +a
fi
$BLOCK_END
EOF
  c_ok "~/.bash_profile にロケール読み込みブロックを追加しました"
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
c_info "=== 4/5 設定の配置 ==="; deploy; install_bash_profile_block
c_info "=== 5/5 サービス ==="; enable_units

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
