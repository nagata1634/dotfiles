# bootstrap — OS インストールの自動化（Fedora Kinoite, PXE + Kickstart）

`fedora-kinoite.ks` は Fedora Kinoite を自動インストールする Kickstart。PXE サーバーは別リポジトリ
[nagata1634/pxe-boot](https://github.com/nagata1634/pxe-boot)（QNAP NAS 上の dnsmasq proxyDHCP + nginx）。

## 全体像（環境を作り直す手順）

| 段階 | 担当 | 内容 |
|---|---|---|
| 1. OS | `fedora-kinoite.ks`（PXE 経由） | パーティション・LUKS・ロケール・ostree deploy・plasmalogin |
| 2. 初回起動 | Plasma Setup（Kinoite 標準） | ユーザー作成 |
| 3. ユーザー環境 | `../install.sh` | レイヤ（要再起動）・フォント・symlink・Flatpak・テーマ・KDE 拡張・authselect・**KDE 設定スナップショットの復元** |
| 4. 確定 | ログアウト → ログイン | ショートカット・仮想デスクトップ・モニタ配置は KWin が起動時に読む |
| 5. 手動 | `pamu2fcfg`、Pika Backup からデータ復元、Bitwarden/ブラウザのログイン | 機器固有・機密は記録しない |

Atomic の Kickstart `%post` はイメージが deploy された直後の状態しか触れず、**`rpm-ostree` による
レイヤリングができない**。`systemd --user` も動いていない。よって `%post` はヒントを置くだけ。

## 完全自動にはならない点

意図的に対話が入る。**公開リポジトリに機密を書かないため**。

- **LUKS パスフレーズ**: `--passphrase` を書かないので Anaconda が尋ねる
- **ユーザーのパスワード**: Plasma Setup で作る（`user --iscrypted` を使う場合は `.ks` 内コメント参照）
- **Yubikey の登録**（`~/.config/Yubico/u2f_keys`）: 機器固有。`install.sh` が未登録なら案内を出す

## 記録している設定（`install.sh` が復元するもの）

- `home/.config/kde-snapshot/`: パネル・ウィジェット・KWin・ショートカット・外観・入力・電源
  （`kde-snapshot save` で更新。壁紙画像のパスは記録しない）
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
