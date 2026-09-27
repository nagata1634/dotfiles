# dotfiles

**Fedora Kinoite（KDE Plasma / Wayland）** の `~/` の層だけを持つスモール構成。
OS・アプリ・`/etc` は [`nagata1634/pxe-boot`](https://github.com/nagata1634/pxe-boot) の Kickstart と初回起動サービスが入れる。

```sh
curl -fsSL https://raw.githubusercontent.com/nagata1634/dotfiles/main/install.sh | bash
```

冪等。symlink → KDE 拡張（Monitor Align / Span Image / Krohnkite）→ WhiteSur テーマ → systemd --user の順。

初回だけ手動で行うこと:

- `kde-snapshot restore` で KDE 設定（と Pika Backup の設定）を戻し、ログアウト→ログイン
- `mkdir -p ~/.config/Yubico && pamu2fcfg > ~/.config/Yubico/u2f_keys`
- データは Pika Backup（NAS）から選択復元。SSH 鍵は Yubikey の resident key から `ssh-keygen -K`

KDE の設定を変えたら `kde-snapshot save` して commit する。罠と理由は [`CLAUDE.md`](CLAUDE.md)。
