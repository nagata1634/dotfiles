# dotfiles

**Fedora Kinoite（KDE Plasma / Wayland）** の個人環境。標準のまま使い、必要なものだけ外部から入れるスモール構成。

```sh
curl -fsSL https://raw.githubusercontent.com/nagata1634/dotfiles/main/install.sh | bash
```

冪等。rpm-ostree レイヤ → symlink → docker-compose → Flatpak → KDE 拡張（Monitor Align / Span Image /
Krohnkite）→ WhiteSur テーマ → authselect → systemd --user の順に入れる。
レイヤを追加したときは再起動してもう一度流す。

初回だけ手動で行うこと:

- `kde-snapshot restore` で KDE 設定（と Pika Backup の設定）を戻し、ログアウト→ログイン
- `mkdir -p ~/.config/Yubico && pamu2fcfg > ~/.config/Yubico/u2f_keys`
- `system/` の usb-wakeup を pkexec で配置（手順は `CLAUDE.md`）
- データは Pika Backup（NAS）から選択復元。SSH 鍵は Yubikey の resident key から `ssh-keygen -K`

KDE の設定を変えたら `kde-snapshot save` して commit する。

| パス | 中身 |
|---|---|
| `home/` | `~/` への symlink 元（fcitx5、環境変数、`.profile`、`.bashrc.d`、user unit、配色、Flatpak override、`kde-snapshot`） |
| `packages.txt` / `flatpaks.txt` | rpm-ostree レイヤ / Flatpak アプリ |
| `system/` | `/etc`・`/usr/local` 側（authselect、usb-wakeup） |
| `bootstrap/` | OS インストール（Kickstart） |
| `CLAUDE.md` | 今の設定の要点と、踏むと壊れる罠 |
