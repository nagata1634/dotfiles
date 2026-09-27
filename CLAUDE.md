# 設計ノート

Fedora **Kinoite**（KDE Plasma 6 / Wayland）の個人環境。**方針はスモール: 標準のまま使い、
必要なものだけ外部から入れる。チェック機構は置かない。**
**担当分け: OS・アプリ（rpm レイヤ / Flatpak / docker-compose）・`/etc`（authselect / usb-wakeup）は
`nagata1634/pxe-boot` の Kickstart と初回起動サービス。この dotfiles は `~/` の層だけ。** ここには「今動いている設定」と「踏むと壊れる罠」だけを書く。
経緯（Sway/Sericea 時代、試して捨てた案）は git 履歴にある（2026-09-27 に圧縮）。

構成: plasmalogin → `startplasma-wayland`、IME は fcitx5 + Mozc（KWin が起動）、タイルは Krohnkite、
ロックは kscreenlocker、ランチャーは KRunner、ブラウザは Brave(Flatpak)。`/var/home` は LUKS 上の btrfs。
アプリストアは **Discover だけ**（ベース同梱で外せず、rpm-ostree 更新の通知も Discover の notifier しか
担っていない。Flathub 専用の Bazaar は二重管理になるので 2026-09-28 に撤去）。

## セッションと環境変数

- GUI の環境変数は `~/.config/environment.d/*.conf` だけで足りる（Plasma の systemd 統合で GUI まで届く。
  `~/.profile` は不要）。**空値の行（`FOO=`）は invalid として無視される**ので、未設定にしたい変数は行ごと書かない
- ロケール: GUI = 日本語は `/etc/locale.conf`（Kickstart の `lang ja_JP.UTF-8`）のまま。素の VT は
  `/etc/profile.d/lang.sh` が `LANG` を en_US にするが `LC_*` は日本語のまま残るので、
  `~/.bashrc.d/90-tty-locale.sh` が対話 VT だけ `C.UTF-8` に落とす（`$-` の対話ガード必須）
- `EDITOR`/`VISUAL` は `~/.bashrc.d/60-editor.sh`（`/etc/profile.d/nano-default-editor.sh` の上書き）
- ssh-agent: `ssh-agent.socket` + `environment.d/10-ssh-agent.conf`。`~/.ssh/config` に `AddKeysToAgent yes`

## PAM・ログイン

- authselect `custom/yuya-auth`（pxe-boot が配置）。
  ログイン画面は Yubikey(u2f) → パスワード（`password-auth` に指紋なし、意図的）。
  ロック画面は kscreenlocker の `kde-fingerprint` で指紋が効く
- **`/etc/plasma-setup-done` が無いと初回ウィザードが毎回走り**、自動ログイン設定を書いて
  `Autologin failed!` を残す → `touch` 済み
- keyring は gnome-keyring（KWallet は使わない）。LUKS があるので Default keyring は空パスワード
  （u2f/指紋ログインでは PAM にパスワードが渡らず自動解錠できないため）。空にするのは seahorse の GUI から。
  **Bitwarden は Secret Service の代わりにならない**（gh・Brave・VS Code が Secret Service 経由）
- VS Code は `~/.vscode/argv.json` の `"password-store": "gnome-libsecret"` が必須
  （KDE だと KWallet を自動選択してしまう）

## IME（fcitx5）

- **KWin に起動させる**: `kwinrc [Wayland] InputMethod=/usr/share/applications/org.fcitx.Fcitx5.desktop`。
  autostart で自力起動させると、パネルにフォーカスが移った瞬間に入力の枠を奪われて日本語が打てなくなる
  （プロセスは生きていて `fcitx5-remote` も応答するので気づきにくい）。autostart 側は
  `~/.config/autostart/org.fcitx.Fcitx5.desktop` に `NotShowIn=KDE;` を足して止める
- `GTK_IM_MODULE` / `QT_IM_MODULE` は設定しない（Wayland ネイティブ経路と衝突する）
- 配列は `us`。切替は `Ctrl+Space` と `Super+Space`（Brave が Ctrl+Space を取るため追加）
- 落ちたときの復旧: `systemd-run --user --unit=fcitx5-manual fcitx5`

## KDE の設定を変えるとき

- `kwinrc` / `kglobalshortcutsrc` / `*-appletsrc` は **KWin・plasmashell が実行中に上書きする**。
  ファイルを直接編集しない
- ショートカットは KWin 内蔵の kglobalaccel に D-Bus で登録する。`setShortcutKeys`（flags=6）なら即座に効く
  （`setForeignShortcutKeys` は記録されるだけで反応しない）。**Shift+数字は記号側のキーで届く**
  （Meta+Shift+3 は `Meta+Shift+#`）ので両方の表現で登録する
- 仮想デスクトップは `qdbus-qt6 org.kde.KWin /VirtualDesktopManager createDesktop`、
  パネルは `qdbus-qt6 org.kde.plasmashell /PlasmaShell evaluateScript`（`kde-scripts/panel-sensors.js`）
- ショートカット・デスクトップ数・InputMethod は KWin が起動時にしか読まない → ログアウトで確定
- 変えたら `kde-snapshot save` → commit（rc 群をコピーで保持。symlink にしないのは KDE が書き換えるため）
- **KWin の起動直後に出力構成を変えると KWin が落ち**、巻き添えで fcitx5 も死ぬ。
  `monitoralign.service` は `After=plasma-plasmashell.service` + `ExecStartPre=sleep 15`

**Krohnkite**: `kwinrc [Plugins] krohnkiteEnabled=true` が要る。`FocusPolicy=ClickToFocus`
（マウス追従だとキーでのフォーカス移動が戻される）。`Meta+L` は `ksmserver` のロックと衝突する。
キーは `Meta+HJKL`（フォーカス）/ `+Shift`（移動）/ `+Ctrl`（リサイズ）、`Meta+1〜0` / `Meta+Shift+1〜0` で
デスクトップ（10 枚）。

## モニタ（Monitor Align）

実体は独立リポジトリ `nagata1634/kwin-monitoralign`（install.sh が Release から導入）。
- 座標は `kscreen-doctor -j` の `pos` と `round(size/scale)`（KWin の論理座標）だけを使う。
  **`xrandr` は ×scale の物理 px なので混ぜない**（混ぜると 769px の隙間ができ、カーソルが画面を渡れなくなる）
- `kscreen-doctor` は**負の座標を黙って拒否する**（終了コード 0）。Y は最小 0 に正規化する
- 外部 2 枚は EDID が同一で MST。接続名（DP-6/7/8）がセッションごとにずれる

## 蓋・サスペンド

- 蓋を閉じたままアンロックすると内蔵画面が復活する KDE のバグ → `kde-lid-unlock-fix.service` が
  アンロックを監視して `kscreen-doctor output.eDP-1.disable` を打ち直す
- **未解決**: 3 画面から蓋を閉じるとパネルが消える。appletsrc の `lastScreen=-1` は逆効果（どこにも出なくなる）
- ドックのキーボードでの復帰（全ハブの USB wakeup）は pxe-boot の `usb-wakeup.sh` が担当

## Flatpak

- **日本語が豆腐になったら**（freedesktop 26.08 ランタイム）: `~/.var/app/<app>/config/fontconfig/fonts.conf`
  に `<dir>/run/host/fonts</dir>` と JP 字形優先を書く（Obsidian で適用済み）

## 再現とバックアップ

PXE + Kickstart（`nagata1634/pxe-boot`）→ 初回ログインで `install.sh` → `kde-snapshot restore`。
データは Pika Backup（NAS、sshfs `~/mnt/qnap-tpbk`）から選択復元する。
- **Pika の除外に `~/mnt` 必須**（無いと NAS 全体を取り込む）
- **Pika の実行中に `qnap-tpbk.service` を restart しない**（borg が落ちてロックが残る）。
  ロックが残ったときは、borg が止まっていることを確かめてから
  `flatpak run --command=borg org.gnome.World.PikaBackup break-lock <repo>`
- 監視の仕組みは置いていないので、ときどき Pika の画面で最終成功日時を見ること
  （2026-06〜09 に 3 か月止まっていても気づかなかった前例がある）

## 構造

```
install.sh
home/        ~/ への symlink 元（~/.config/fcitx5 などはディレクトリ単位、
             ~/.bashrc.d と systemd/user はファイル単位）
```

公開リポジトリなので機密は入れない。
