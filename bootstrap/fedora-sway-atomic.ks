# Fedora Sway Atomic (Sericea) の自動インストール定義（Kickstart）。
#
# これは OS 層だけを作る。ユーザー環境（設定・フォント・レイヤリング）は
# 初回ログイン後に ~/.dotfiles/install.sh が行う。
#
# なぜ分かれているか:
#   Atomic の Kickstart %post ではイメージが deploy された直後の状態しか触れず、
#   rpm-ostree によるパッケージレイヤリングができない。また systemd --user も動いて
#   いないためユニットの有効化もできない。よって %post では clone までに留める。
#
# 機密は一切書かない（このリポジトリは公開）:
#   - LUKS パスフレーズは指定せず、インストール中に対話で入力する
#   - ユーザーのパスワードも書かず、初回起動の設定画面に任せる
#
# 検証は VM で行う。手順は bootstrap/README.md を参照。

# ----- 基本 -------------------------------------------------------------
lang ja_JP.UTF-8
keyboard us
timezone Asia/Tokyo --utc

# TTY を英語に保つ方針だが、それは Home 側（~/.bashrc.d/90-tty-locale.sh）で行う。
# システムの lang は ja_JP.UTF-8 のままにしておく（CLAUDE.md「ロケール分離」参照）。

# ----- ネットワーク -----------------------------------------------------
# %post で GitHub から clone するため、インストール時にネットワークが必要。
network --bootproto=dhcp --device=link --activate

# ----- ユーザー ---------------------------------------------------------
# Kickstart にパスワード（ハッシュを含む）を書かないため、初回起動の設定画面で作る。
rootpw --lock
firstboot --reconfig

# Kickstart で作りたい場合は次の 2 行を有効にし、ハッシュを自分で生成して入れる。
# ハッシュ生成: openssl passwd -6
#   （生成したハッシュは公開リポジトリにコミットしないこと）
#user --name=yuuya --groups=wheel --iscrypted --password=<ここにハッシュ>
#firstboot --disable

# ----- ディスク ---------------------------------------------------------
# LUKS2 + btrfs。パスフレーズは --passphrase を書かないので Anaconda が対話で尋ねる。
# 現在の実機構成: nvme0n1p3 を LUKS2 で暗号化し、その上の btrfs に /var/home を置く。
# ディスク名やサイズは環境ごとに違うため autopart に任せている。
# 手動で切る場合の例は下部のコメントを参照。
ignoredisk --only-use=nvme0n1
clearpart --all --initlabel --disklabel=gpt
autopart --type=btrfs --encrypted --luks-version=luks2

# 手動でパーティションを切る場合の例（autopart をコメントアウトしてから使う）:
#part /boot/efi --fstype=efi  --size=600
#part /boot     --fstype=ext4 --size=1024
#part btrfs.01  --grow --encrypted --luks-version=luks2
#btrfs none --label=fedora btrfs.01
#btrfs /        --subvol --name=root fedora
#btrfs /var/home --subvol --name=home fedora

# ----- インストールソース -----------------------------------------------
# ISO 内の ostree リポジトリから入れる。ref は ISO のバージョンで変わるので、
# インストーラの shell（Ctrl+Alt+F2）で確認すること:
#   ostree --repo=/ostree/repo refs
ostreesetup --osname="fedora" --url="file:///ostree/repo" --ref="fedora/44/x86_64/sericea" --nogpg

# ----- SELinux / ファイアウォール --------------------------------------
selinux --enforcing
firewall --enabled

# ----- 再起動 -----------------------------------------------------------
reboot --eject

# ----- インストール後 ---------------------------------------------------
%post --erroronfail --interpreter=/bin/bash
set -euo pipefail

# 初回ログイン時に dotfiles の適用を促すヒントを置く。
# ここで install.sh を実行しないのは、rpm-ostree のレイヤリングと systemd --user が
# この時点では使えないため（ファイル冒頭のコメント参照）。
cat > /etc/profile.d/zz-dotfiles-hint.sh <<'HINT'
# dotfiles が未適用なら案内を出す（install.sh が symlink を張ると消える）。
if [ -n "${BASH_VERSION:-}" ] && [ ! -L "$HOME/.config/sway" ]; then
    printf '\n\033[1;34m::\033[0m dotfiles が未適用です。次を実行してください:\n'
    printf '    curl -fsSL https://raw.githubusercontent.com/nagata1634/dotfiles/main/install.sh | bash\n\n'
fi
HINT
chmod 644 /etc/profile.d/zz-dotfiles-hint.sh

%end
