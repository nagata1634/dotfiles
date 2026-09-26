# bootstrap — OS インストールの自動化（Fedora Kinoite, PXE + Kickstart）

`fedora-kinoite.ks` は Fedora Kinoite を自動インストールする Kickstart。PXE サーバーは別リポジトリ
[nagata1634/pxe-boot](https://github.com/nagata1634/pxe-boot)（QNAP NAS 上の dnsmasq proxyDHCP + nginx）。

## 全体像（環境を作り直す手順）

| 段階 | 担当 | 内容 |
|---|---|---|
| 0. 事前 | `backup-check` / Pika Backup | **最終成功が 24h 以内**であること（`backup-check`）。直前に Pika で「今すぐバックアップ」を 1 回 |
| 1. OS | `fedora-kinoite.ks`（PXE 経由） | パーティション・LUKS（対話）・ロケール・ostree deploy |
| 2. 初回起動 | Plasma Setup（Kinoite 標準） | ユーザー作成 |
| 3. ユーザー環境 | `../install.sh` | レイヤ（要再起動→再実行）・フォント・symlink・Flatpak・テーマ・KDE 拡張・authselect・**KDE 設定と Pika 設定のスナップショット復元** |
| 4. 鍵 | 手動（Yubikey） | `pamu2fcfg > ~/.config/Yubico/u2f_keys`（PAM）、`ssh-keygen -K`（NAS 用 resident key の復元）→ `systemctl --user start qnap-tpbk` でマウント確認 |
| 5. データ | Pika Backup | Pika を開く → 復元された設定に repo が見えている → パスフレーズ（Bitwarden）→ **アーカイブから選択復元**（下記） |
| 6. 確定 | ログアウト → ログイン | ショートカット・仮想デスクトップ・モニタ配置は KWin が起動時に読む。ブラウザ/Bitwarden のログインは手動 |

### 5 の「選択復元」

`~` 全体を戻すと `install.sh` が置いた symlink や `.config` を上書きしてしまうため、データだけを選ぶ:

- 復元する: `Documents` `Pictures` `Music` `Videos` `Downloads` `.ssh`（従来の `yuuya-nas` 鍵を含む）
  `.config/Yubico` `.local/share/keyrings` `.var/app/*`（Flatpak アプリのデータ。Pika 自身の設定は除く）
- 復元しない: `.config`（`kde-snapshot` が担当）、`.local/bin` `.bashrc*` `.profile`（dotfiles）、
  `.local/share/flatpak`、`.cache`、`mnt`

### NAS 鍵の二重化（循環依存の解消）

NAS への sshfs は SSH 鍵が要り、鍵はバックアップの中、バックアップは NAS の中——という循環を、
**Yubikey の resident key**（秘密をどこにも保存しない。`ssh-keygen -K` で再生成）で断つ。日常は従来の
ed25519 鍵（Bitwarden に控え）。NAS の `authorized_keys` には 2 本登録し、`~/.ssh/config` と
`qnap-tpbk.service` は両方の `IdentityFile` を指す（無い方は無視される）。

Atomic の Kickstart `%post` はイメージが deploy された直後の状態しか触れず、**`rpm-ostree` による
レイヤリングができない**。`systemd --user` も動いていない。よって `%post` はヒントを置くだけ。

## 完全自動にはならない点

意図的に対話が入る。**公開リポジトリに機密を書かないため**。

- **LUKS パスフレーズ**: `--passphrase` を書かないので Anaconda が尋ねる
- **ユーザーのパスワード**: Plasma Setup で作る（`user --iscrypted` を使う場合は `.ks` 内コメント参照）
- **Yubikey の登録**（`~/.config/Yubico/u2f_keys`）: 機器固有。`install.sh` が未登録なら案内を出す
- **borg のパスフレーズ**（Pika）: keyring にしか無い。Bitwarden に控えておく

## 記録している設定（`install.sh` が復元するもの）

- `home/.config/kde-snapshot/`: パネル・ウィジェット・KWin・ショートカット・外観・入力・電源、
  **Pika Backup の設定**（repo の場所・対象・スケジュール）（`kde-snapshot save` で更新。壁紙画像のパスは記録しない）
- `flatpaks.txt` + `home/.local/share/flatpak/overrides/`
- `packages.txt`（rpm-ostree レイヤ）、`fonts.txt`
- `KDE_PACKAGES`（Monitor Align / Span Image / Krohnkite = GitHub Release）、`THEME_REPOS`（WhiteSur）
- `system/authselect/yuya-auth/`（PAM: Yubikey → 指紋 → パスワード）

## 検証

```sh
ksvalidator bootstrap/fedora-kinoite.ks     # pykickstart（toolbox 内で dnf install pykickstart）
```

VM で通してから実機へ。VM は `virt-install --pxe --network bridge=...` で NAS の PXE に乗せるか、
`--cdrom` の Kinoite ISO に `inst.ks=http://NAS/ks/fedora-kinoite.ks` を付ける。
`ostreesetup --ref` は ISO のバージョンで変わるので、`pxe-boot/setup-iso.sh` の出力と合わせる。

**Ignition は使えない** — Fedora CoreOS 専用。Kinoite は Kickstart。
