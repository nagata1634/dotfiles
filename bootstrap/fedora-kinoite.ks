# Fedora Kinoite の自動インストール定義（Kickstart）。PXE + HTTP で配る前提。
#
# これは OS 層だけを作る。ユーザー環境（設定・Flatpak・テーマ・KDE 設定のスナップショット）は
# 初回ログイン後に ~/.dotfiles/install.sh が行う（bootstrap/README.md「2 層」参照）。
#
# なぜ分かれているか:
#   Atomic の Kickstart %post ではイメージが deploy された直後の状態しか触れず、
#   rpm-ostree によるパッケージレイヤリングができない。systemd --user も動いていない。
#
# 機密は一切書かない（このリポジトリは公開）:
#   - LUKS パスフレーズは指定せず、インストール中に対話で入力する
#   - ユーザーのパスワードも書かず、初回起動のセットアップ（plasma-setup）に任せる
#
# 検証: ksvalidator bootstrap/fedora-kinoite.ks

# ----- 基本 -------------------------------------------------------------
lang ja_JP.UTF-8
keyboard us
timezone Asia/Tokyo --utc
# TTY を英語に保つのは Home 側（~/.bashrc.d/90-tty-locale.sh）。システムの lang は ja のまま。

# ----- ネットワーク -----------------------------------------------------
network --bootproto=dhcp --device=link --activate

# ----- ユーザー ---------------------------------------------------------
# パスワード（ハッシュ含む）を書かないため、初回起動の Plasma Setup（ウィザード）でユーザーを作る。
# Kinoite は plasma-setup.service が /etc/plasma-setup-done が無い間ウィザードを出す。
rootpw --lock

# Kickstart で作りたい場合は次の 2 行を有効にし、ハッシュを自分で生成して入れる（コミット禁止）。
# ハッシュ生成: openssl passwd -6
#user --name=yuuya --groups=wheel --iscrypted --password=<ここにハッシュ>
# その場合は %post で touch /etc/plasma-setup-done してウィザードを止める。

# ----- ディスク ---------------------------------------------------------
# LUKS2 + btrfs。パスフレーズは --passphrase を書かないので Anaconda が対話で尋ねる。
# 実機: nvme0n1p3 を LUKS2 で暗号化し、その上の btrfs に /var/home。サイズは autopart に任せる。
ignoredisk --only-use=nvme0n1
clearpart --all --initlabel --disklabel=gpt
autopart --type=btrfs --encrypted --luks-version=luks2

# ----- インストールソース（ostree）----------------------------------------
# Kinoite の ISO は ostree リポジトリを ISO ルートではなく **images/install.img（stage2 の rootfs）の
# /ostree/repo に持つ**（ISO 同梱の interactive-defaults.ks と同じ指定）。PXE では inst.stage2 で
# install.img を NAS から取るので、インストーラ内では file:///ostree/repo として見える。
# ref は ISO のバージョンで変わる: pxe-boot/setup-iso.sh の出力、または
#   7z l images/install.img | grep refs/heads
ostreesetup --nogpg --osname="fedora" --remote="fedora" --url="file:///ostree/repo" --ref="fedora/44/x86_64/kinoite"
# ISO 無しでネット経由（遅い）:
#ostreesetup --osname="fedora" --remote="fedora" --url="https://ostree.fedoraproject.org" --ref="fedora/44/x86_64/kinoite"

# ----- SELinux / ファイアウォール --------------------------------------
selinux --enforcing
firewall --enabled

# ----- 再起動 -----------------------------------------------------------
reboot

# ----- インストール後 ---------------------------------------------------
%post --erroronfail --interpreter=/bin/bash
set -euo pipefail

# ostree remote を公式に向け直す（以後の rpm-ostree upgrade は fedoraproject.org から）。
# インストール時は ISO 内の repo（file:///ostree/repo、--nogpg）を使ったので、GPG 検証付きの公式 remote に置き換える。
ostree remote delete fedora || true
ostree remote add --set=gpg-verify=true --set=gpgkeypath=/etc/pki/rpm-gpg/ fedora https://ostree.fedoraproject.org 2>/dev/null \
  || ostree remote add --no-gpg-verify fedora https://ostree.fedoraproject.org

# 初回ログイン時に dotfiles の適用を促すヒント（install.sh が ~/.profile を symlink にすると消える）。
cat > /etc/profile.d/zz-dotfiles-hint.sh <<'HINT'
if [ -n "${BASH_VERSION:-}" ] && [ ! -L "$HOME/.profile" ]; then
    printf '\n\033[1;34m::\033[0m dotfiles が未適用です。次を実行してください:\n'
    printf '   curl -fsSL https://raw.githubusercontent.com/nagata1634/dotfiles/main/install.sh | bash\n\n'
fi
HINT
%end
