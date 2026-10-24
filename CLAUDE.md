# 設計ノート

Fedora **Kinoite**（KDE Plasma 6 / Wayland）の個人環境。**方針はスモール: 標準のまま使い、
必要なものだけ外部から入れる。チェック機構は置かない。**
**担当分け: OS・アプリ（rpm レイヤ / Flatpak / docker-compose）・`/etc`（authselect / usb-wakeup）は
`nagata1634/pxe-boot` の Kickstart と初回起動サービス。この dotfiles は `~/` の層だけ。** ここには「今動いている設定」と「踏むと壊れる罠」だけを書く。
経緯（Sway/Sericea 時代、試して捨てた案）は git 履歴にある（2026-09-27 に圧縮）。

構成: plasmalogin → `startplasma-wayland`、IME は fcitx5 + Mozc（KWin が起動）、タイルは HyprKwin、
ロックは kscreenlocker、ランチャーは KRunner、ブラウザは Brave(Flatpak)（標準ブラウザは `browser-fallback.desktop`＝
`~/.local/bin/browser-open` が Brave で開き、10 秒以内に失敗したら Firefox で開く。2026-10-20 本人指示）。`/var/home` は LUKS 上の btrfs。
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

**タイル = HyprKwin**（2026-10-24 に Krohnkite から切替。本人が Hyprland の dwindle＝螺旋状の配置と、分割1つ単位の
向き切替 `toggleSplit` を望んだため。Krohnkite の Spiral は分割の向きが固定で回せず、外付けスクリプトでも足せない）。
`kwinrc [Plugins] hyprkwinEnabled=true`、`[Script-hyprkwin]` で `PerOutputWorkspaces` / `AutoCreateDesktops` /
`StartOnFirstDesktop` を false（デスクトップ 10 枚・`Meta+1〜0` の従来の使い方を保つ）。Krohnkite は無効化・キー全解除で残置。
キー: `Meta+HJKL`（フォーカス、矢印も可）/ `+Shift`（移動＝Hyprland の movewindow。隣に差し込み、端ならその方向のモニターへ。
下にモニターが無ければ何もしない）/ `+Ctrl`（境目の移動）/ `Meta+R`（分割の向き切替）/ `Meta+Shift+R`（分割の左右入替）/
`Meta+F`（フロート）/ `Meta+\`（レイアウト切替）/ `Meta+/`（キー一覧。既定の `Meta+K` は上フォーカスに使う）。
**HyprKwin の既定キーは Hyprland 式で既存と 42 件衝突した**ので、Plasma 側（デスクトップ切替・`Meta+Tab`・ズーム等）を残し
HyprKwin 側を外した。同梱の `hyprkwin-shortcuts.py apply` は全部 HyprKwin に渡すので使わない。

**仮想デスクトップは動的（GNOME 式）**（2026-10-24 本人指示）: Temporary Virtual Desktops（Ubiquitine/temporary-virtual-desktops）で
空になったデスクトップを消し、`oneSpare=true` で末尾に空きを 1 つ保つ。表示中のデスクトップと作成直後 1.5 秒は消さない。
番号キーは HyprKwin 側（`desktopN` / `moveToDesktopN`、`AutoCreateDesktops=true`）に移した。KWin 標準の「デスクトップ N へ」は
存在しない番号では効かないため。消えると番号は繰り上がる（Mac と同じ）。**日本語の既定名「デスクトップ N」は上流が振り直さない**
（英語 `Desktop N` 決め打ち）→ 修正 PR を出した（Ubiquitine/temporary-virtual-desktops#10）。取り込まれるまでは `install.sh`
で入る公式リリースだと名前がずれる（手元は PR 版を入れてある）。

**Konsole のペインも Vim 式**（2026-10-25 本人指示）: `Ctrl+Shift+H/J/K/L` でペイン移動（矢印も残す）。既定で `Ctrl+Shift+H` は
「ビューの切り離し」（キー解除、メニューに残る）、`Ctrl+Shift+K` は「スクロール履歴の消去とリセット」（`Ctrl+Shift+X` へ移動）だった。
Konsole のキーは `~/.local/share/kxmlgui5/konsole/{konsoleui,sessionui}.rc` の `<ActionProperties>` で上書きする。KXmlGui は手元の
rc を **GUI 定義ごと** 使うので、Konsole 26.08.1 の原本（gui version 20 / 36）を丸ごと置いて末尾に足してある。Konsole が rc の version
を上げると原本側に置き換わり、ActionProperties だけ引き継がれる（KXmlGui の仕様）。kde-snapshot の DATA_DIRS で記録。

フォーカスは `FocusPolicy=FocusFollowsMouse` + `DelayFocusInterval=300`（2026-10-24 本人指示）。マウスを動かしたときだけ移るので、
キーで移したフォーカスが保たれる。**FocusUnderMouse は不可**（カーソル下に常に戻す）。
ロックのキーは外した（`Meta+L` はフォーカスに使う。本人が不要と判断。Screensaver 専用キーのみ）。Spectacle の領域録画（`.desktop` 既定の
`Meta+R`/`Meta+Shift+R`）・Show Desktop(`Meta+D`)・Edit Tiles(`Meta+T`)・システム設定(`Meta+I`)・絵文字(`Meta+.`)・
クイックタイル（`Meta+矢印`）も外してある。
**キーの重複確認は D-Bus の `allShortcutInfos` を全コンポーネント分走査する**（`.desktop` 由来の既定キーは
`kglobalshortcutsrc` に書かれないので、ファイル grep では漏れる）。

## メールのウィジェット（Mail Widget）

実体は独立リポジトリ `~/Documents/plasma-mailwidget`（MIT・未公開）。ウィジェットは `~/.local/share/plasma/plasmoids/dev.yuya.mailwidget` に symlink。
- ウィジェット用の Thunderbird は**ふつうの Thunderbird と別物**: 専用プロファイル `~/.var/app/org.mozilla.thunderbird_esr/.thunderbird/mailwidget`、
  アプリ名 `thunderbird-widget`（`--name`/`--class`）、`thunderbird-bg.service` が裏で動かす。ランチャーから開くのは既定のプロファイルのふつうのアプリ（2026-10-20 本人指示）
- KWin のルール（`kwinrulesrc`）は `thunderbird-widget` のメインのウィンドウだけをタスクバーから外す。最小化はアドオンがする
- 受け口 `mailbridge.service`（127.0.0.1:47819・鍵は `~/.config/mailbridge/token`、アドオンの設定画面に貼る）
- 導入・やり直しは `package/contents/install-bridge.sh --kwin-rule`
- **カレンダーのウィジェット**（`dev.yuya.calendarwidget`、同じリポジトリの `calendar-package/`）は Thunderbird を通さない。
  受け口が Google カレンダーの「iCal 形式の非公開アドレス」（標準の ICS）を 10 分ごとに読み、`python3-dateutil`（ベースに同梱）で繰り返しを展開する。
  アドレスは `~/.config/mailbridge/calendars.json`（600）だけに置く（ウィジェットの設定＝appletsrc に入れると公開の dotfiles に出る）。
  通知は予定ごとの VALARM の時刻に、ウィジェットで「通知する」にしたカレンダーだけ（`~/.config/mailbridge/calendar.json`）。
  試験版の calendar API は使わない（2026-10-20 本人方針「できる限り標準」）。Google の「誕生日」は ICS が無いので対象外
- **ToDo のウィジェット**（`dev.yuya.taskwidget`、`task-package/`）だけは標準の手段が無いので試験版を使う（本人了承）:
  ウィジェット用 Thunderbird に「Provider for Google Calendar」（ATN 署名済み）で Google ToDo のリストだけを登録し、
  自作アドオンが同梱の calendar experiment（provider の起動部品も登録が必要）で読み書きする。予定のカレンダーはここに登録しない（重複する）。
  試験版を動かすには `extensions.experiments.allowed` に両アドオンの ID が要る（install-bridge.sh の user.js）
- ふつうの Thunderbird のリマインダー画面は止めた（`calendar.alarms.show=false`）。予定の通知はカレンダーのウィジェットだけ

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

- **日本語フォントは global override で全アプリ一括**（アプリ別の fonts.conf は置かない。2026-09-28 本人指示）:
  `overrides/global` の `FONTCONFIG_FILE` が `home/.config/flatpak-fonts/fonts.conf` を指し、そのフォルダだけ `:ro` で許可。
  中身は `/etc/fonts/fonts.conf` を include し、`<dir>/run/host/fonts</dir>` と JP 字形優先を足すだけ
  - 理由: freedesktop 26.08 ランタイムは `/run/host/fonts` を `/usr/share/fonts` として扱い、ランタイム自身の同名キャッシュ
    （`/usr/lib/fontconfig/cache`）と衝突してホストのフォントが 0 件になる。`fc-cache -f` では直らない
  - **toolbox から共有の `~/.cache/fontconfig` に書かせない**。toolbox の `/usr/share/fonts` の控えを Flatpak がホストの控えと
    取り違え、GNOME 系も含め日本語が消える（作業用 Chrome の `browser-fonts.conf` は専用 `<cachedir>` を先頭に置いた）
  - 確認: `flatpak run --command=sh <app> -c 'fc-list :lang=ja | wc -l; fc-cat -v /run/host/fonts | sed -n 2p'`
    （件数が 0 か、控えが `/usr/lib/fontconfig/cache` なら本件）

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
