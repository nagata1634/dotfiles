# 設計ノート

Fedora **Kinoite**（KDE Plasma / Wayland）上の環境。2026年8月末〜9月にかけて
Sway(Sericea)から完全移行した（COSMICも試したが fcitx5 が動かず断念、という経緯を経ている）。
各設定ファイルには要点だけを書き、「なぜそうなっているか」はこのファイルに集約している。
設定を変える前にここを読むこと。

- 構成: **Plasma Login Manager(`plasmalogin`、KDE 標準・ベース同梱)** → `startplasma-wayland`、
  IME は fcitx5 + Mozc（KWin 起動）、
  タイル管理は Krohnkite（KWin スクリプト）
- ロック画面は KDE 標準の kscreenlocker を使う（Sway 時代の「ロックを持たない設計」は廃止。
  詳細は後述「蓋を閉じたときの挙動」）
- ランチャーは KRunner（Meta+Space）、ターミナルは Konsole/foot、ブラウザは Brave(Flatpak)
- `/var/home` は LUKS 上の btrfs（ディスク全体が暗号化済み）
- **Sericea(Sway) デプロイメントは切り戻し用に `rpm-ostree` で pin したまま残してある**。
  日常使いはしない。詳細は末尾「旧構成: Sway(Sericea) への切り戻し」

---

## GUI セッションの環境

**ログインは Plasma Login Manager（`plasmalogin.service`、`Alias=display-manager.service`）**。
2026-09-27 に greetd@tty1 + tuigreet から切り替えた（写しは `legacy/greetd/`）。Fedora 44 Kinoite
の標準はこれで、SDDM はもう同梱されていない（`plasma-login-manager` が後継）。セッションは
`/etc/plasmalogin/wayland-session` が `bash --login` で `~/.bash_profile` → `~/.profile` を読んで
から `startplasma-wayland` を exec するので、ロケール・ssh-agent の経路は greetd 時代と同じ。
加えて `~/.config/environment.d/*.conf` も Plasma の systemd 統合で GUI セッションまで届く
（`systemctl --user show-environment` で `LANG=ja_JP.UTF-8` / `SSH_AUTH_SOCK` を確認済み）。
`environment.d` は **空値の行（`FOO=`）を invalid syntax として無視する**ので、未設定にしたい
変数は行ごと書かない。

**PAM**: 標準の `/usr/lib/pam.d/plasmalogin` は `substack password-auth`。この環境の authselect
（`custom/yuya-auth`）は `password-auth` に `pam_fprintd` を入れていないため、**ログイン画面は
Yubikey(pam_u2f) → パスワード、指紋なし**（意図的。`/etc` に差分を作らない判断）。指紋を足すなら
`/etc/pam.d/plasmalogin` を新規作成して `substack system-auth` にする（上流ファイルは触らない）。
ロック画面（kscreenlocker）は `kde` + `kde-fingerprint` の並列スタックで指紋が効く。

**Kinoite 固有**: `fedora-kinoite-plasmalogin-workaround.service` が `/etc/shadow` に `plasmalogin`
ユーザーを補う（forge.fedoraproject.org/kde/SIG/issues/684）。また **`plasma-setup.service`
（初回セットアップウィザード）は `/etc/plasma-setup-done` が無いと毎回起動時に走り**、
`plasma-setup` ユーザーの自動ログイン設定を書いてログインを 1〜2 秒遅らせ `Autologin failed!`
を残す。このユーザーは Sericea 時代に作られておりウィザードを通っていないため、
`touch /etc/plasma-setup-done`（ウィザード自身の完了マーカー）で止めてある。

**KWin 起動直後の出力変更は危険**: plasmalogin 移行後の 2 回目の起動で、KWin 起動 1〜2 秒後に
`monitoralign-daemon` が `kscreen-doctor` で配置を適用したタイミングで KWin が
`DrmGpu::pageFlipHandler` で SIGSEGV した（`coredumpctl`）。KWin は wrapper が再起動するが、
KWin が起動していた fcitx5 は巻き添えで死に、再起動後の KWin が起動し直す fcitx5 は D-Bus 名の
衝突で失敗する → 日本語入力が無い状態になる。対処: `monitoralign.service` に
`After=plasma-plasmashell.service` と `ExecStartPre=sleep 15` を入れ、デスクトップが出揃ってから
動かす。復旧は `systemd-run --user --unit=fcitx5-manual fcitx5`（KWin の `reconfigure` や
`/VirtualKeyboard` の `mode` トグルでは IM を起動し直せなかった）。

## ロケール分離（GUI = 日本語 / TTY = 英語）

**方針は Sway 時代と同じ**: GUI は日本語、素の VT は英語。`/etc/profile.d/lang.sh` が
`TERM=linux` かつ実 tty のログインシェルで CJK ロケールを `en_US.UTF-8` に強制置換する
仕組み自体は DE に依存しない（`/etc` は変更していない）。

**Kinoite での違い**: plasmalogin の `wayland-session` は `bash --login` で `~/.profile` を読むので橋渡しは維持されるが、そもそも
Sway 時代に必須だった「`~/.profile` で `lang.sh` の後に上書きする」という橋渡しが
機能していない可能性がある。それでも `systemctl --user show-environment` は正しく
`ja_JP.UTF-8` を返しているため、**`~/.config/environment.d/90-locale.conf` が
単体で効いている**とみられる（Sway 時代に「systemd --user からは sway の環境が見えないため
橋渡しが要る」としていた理由が、Plasma のセッション管理では当てはまらない可能性）。
`~/.profile` 自体は install.sh で今も配置されるが、Kinoite 環境での実効性は未確認。

`locale-audit`（`~/.local/bin`）で監査できる（DE に依存しないツール）。

---

## 常駐ツールの起動元マップ

Sway 時代に `systemd --user` で有効化していたユニットのうち、**Plasma 純正機能に
置き換わったものが `enabled` のまま残っている**（`install.sh` の `ENABLE_UNITS` が
まだ Sway 時代のものを含んでいるため）。2026-09-14 確認時点、`systemctl --user
is-active` はいずれも `inactive`（実害は今のところ無いが、クリーンアップ候補）:

| ユニット | Sway での役割 | Kinoite での位置づけ |
|---|---|---|
| `waybar.service` | ステータスバー | Plasma パネルに置き換わり不要。要クリーンアップ |
| `swayidle.service` | アイドル検知・サスペンド連鎖 | powerdevil (kscreenlockerrc/powerdevilrc) に置き換わり不要 |
| `sway-trackpad-reset.service` | ログイン直後の Magic Trackpad 入れ直し | libinput 層の問題は DE 非依存のはずだが、Kinoite で同じ症状が出るか未検証。当面は残す |

**Kinoite で新たに常駐しているもの**:

| ツール | 起動元 | 備考 |
|---|---|---|
| fcitx5 | KWin（`kwinrc` の `[Wayland] InputMethod`） | autostart 経由ではない。詳細は次節 |
| Krohnkite | KWin スクリプト（`kwinrc` `[Plugins] krohnkiteEnabled=true`） | タイル管理。詳細は次々節 |
| `kde-lid-unlock-fix.service` | `systemd --user`（`plasma-workspace.target` に `PartOf`） | 蓋を閉じた状態でのアンロック時、内蔵ディスプレイを無効化し直す。詳細は「蓋を閉じたときの挙動」 |
| `usb-wakeup.service` | `/etc/systemd/system`（root、`pkexec` で手動設置） | DE 非依存。詳細は「サスペンドからの復帰源」 |
| gnome-keyring | `systemd --user` : `gnome-keyring-daemon.service` | Sway 時代と同じ（後述「キーリング」） |
| ssh-agent | `systemd --user` : `ssh-agent.socket` | Sway 時代と同じ |

---

## IME（fcitx5）— KWin に起動させる必要がある

Plasma Wayland では**入力メソッドのプロセスを KWin に起動させなければならない**
（System Settings → キーボード → 仮想キーボード → Fcitx 5 に相当）。fcitx5 が XDG autostart で
自力起動して `input-method-v2` を掴む形は非公式な経路で、**パネル/dock にフォーカスが移り
KWin が仮想キーボードを再調停した瞬間に枠を奪われ、fcitx5 は自力で復帰しない**
（画面下の dock を開くと打てなくなる、という形で再現した）。

**症状の見分け方**: 壊れても `fcitx5` プロセスは生きており `fcitx5-remote -o` も応答する
（D-Bus 上の状態は嘘で、入力コンテキストだけが死んでいる）。復旧は fcitx5 の再起動のみ。

**正しい構成**:

```sh
kwriteconfig6 --file kwinrc --group Wayland --key InputMethod \
  /usr/share/applications/org.fcitx.Fcitx5.desktop
```

KWin はこのキーを**セッション起動時にしか読まない**（reconfigure では反映されない）。
加えて `~/.config/autostart/org.fcitx.Fcitx5.desktop` に system 版をコピーし
`NotShowIn=KDE;` を追記する（`Hidden=true` ではなく `NotShowIn` を使うのが要点。
これなら Sericea にロールバックすれば従来どおり自動起動する）。KWin と autostart の
二重起動は `Unable to request dbus name` で片方が死ぬため排他にすること。

復旧手段: `systemctl --user restart app-org.fcitx.Fcitx5@autostart.service`
（KDE で autostart を止めた後はこのユニットが無いので `fcitx5 &` を直接叩く）。

**外れた対処（繰り返さないこと）**:
- ❌ `GTK_IM_MODULE=fcitx` / `QT_IM_MODULE=fcitx` → Wayland ネイティブ経路と併用になり警告。
  空にしておくのが KDE でも正しい
- ❌ セッション確立後に fcitx5 を再起動する回避策 → 起動時競合という誤診。壊れるのは
  フォーカス遷移時

**キーボード配列は `us`**。IME 切替キーは実質 `Ctrl+Space` 一択。Brave が `Ctrl+Space` を
Leo AI に取るため `Super+space` を `TriggerKeys` に追加してある
（`fcitx5/config` の `Hotkey/TriggerKeys`。`EnumerateGroupForwardKeys` は死に設定だったので
空けて転用した）。

---

## タイル管理（Krohnkite）

KWin(Wayland) 上で [Krohnkite](https://github.com/anametologin/krohnkite)（動的タイル管理の
KWin スクリプト）を導入。2026-09-07 に一度設定したが、**2026-09-14 時点でキーバインド設計が
未適用のまま残っている**（要修正、次節「既知の未解決/未適用」参照）。

**罠1: インストール済み≠有効化済み**。`~/.config/kwinrc` の `[Plugins]` に
`krohnkiteEnabled=true` が無いと動かない。`[Script-krohnkite]` の設定値は有効/無効と無関係に残る。

**罠2: polonium が同時インストールされていた**。同じ動的タイルスクリプトが2つ入っていて
`kglobalshortcutsrc` に polonium 側の `H/J/K/L` 系ショートカットが残留する。
`poloniumEnabled=false` にしてスクリプト自体を無効化しても、**kglobalaccel には
登録済み扱いのままキーが衝突する**ので、対象キーを明示的に `none` で解除する必要がある。

**罠3: `Meta+L` が画面ロックと衝突**。Krohnkite の `Meta+L`（Focus Right）ではなく、
`[ksmserver]` グループの `Lock Session=Screensaver\tMeta+L` という**別コンポーネント**が
キーを握っていた。`kwin` グループしか見ないと気づけない。

**罠4: `FocusPolicy=FocusUnderMouse` だとキーボードフォーカス移動が効かない**。
マウス下のウィンドウに自動フォーカスが戻るため、`Meta+H/J/K/L` でフォーカス移動しても
即座に元に戻る。`ClickToFocus` に変更して解決（現状もこの設定のまま）。

**罠5（2026-09-27 に真因確定）: Plasma 6.7 のグローバルショートカットは KWin 本体が握っている**。
`busctl --user status org.kde.kglobalaccel` の所有者は `kwin_wayland`（`plasma-kglobalaccel.service`
は static で動いていない）。KWin は起動時に `kglobalshortcutsrc` を読み、**終了時に自分の
メモリ上の状態で書き戻す**ので、ファイルを `kwriteconfig6` で書き換えても反映されず、ログアウトで
元に戻る（これが「設計したのに未適用」の正体）。`qdbus-qt6 org.kde.KWin /KWin reconfigure` も
ショートカットは読み直さない。**正しい変更方法は稼働中の D-Bus API**:

```sh
# 例: kwin の "Switch to Desktop 1" を Meta+1 に（キーは QKeySequence().toCombined() の整数）
busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel \
  setForeignShortcutKeys 'asa(ai)' 4 kwin "Switch to Desktop 1" "" "" 1 4 268435505 0 0 0
# 解除は配列長 0。確認は shortcutKeys as 4 <component> <action> "" ""
```

**ただし `setForeignShortcutKeys` はキーを記録するだけで待ち受けが有効にならない**（実機で
Meta+2 が無反応だった）。`setShortcutKeys`（第3引数 flags = 6 = SetPresent|NoAutoloading）で
登録すると即座に効く。もう1つの罠: **Shift+数字は記号側のキーで届く**（US 配列で Meta+Shift+3 は
KWin には `Meta+Shift+#` として来る）ので、`Window to Desktop N` には `Meta+Shift+N` と
`Meta+Shift+<記号>`・`Meta+<記号>` の3表現を併記して登録してある（実機で移動を確認済み）。仮想デスクトップ数も同様に `kwinrc [Desktops] Number` の書き換えでは
増えず、`qdbus-qt6 org.kde.KWin /VirtualDesktopManager createDesktop <pos> <name>` で増やす。

**キーバインド設計**（Sway の `$mod+hjkl` を素に設計。テンキー非依存）:
- Krohnkite デフォルトの `Meta+H/J/K/L`（フォーカス）・`Shift+H/J/K/L`（移動）・
  `Ctrl+H/J/K/L`（リサイズ）は Sway 設定と完全一致していたためそのまま採用
- `Meta+1〜0`: 仮想デスクトップ切替に変更する設計（旧デフォルトの「タスクバー Pin 留め
  アプリ起動」を上書き。デスクトップ数も 2→10 に拡張）
- `Meta+Shift+1〜0`: ウィンドウを指定デスクトップへ移動
- `Meta+BracketRight/Left`, `Meta+Shift+BracketRight/Left`: デスクトップ前後切替/
  ウィンドウ移動（Sway workspace cycle 相当）
- `Meta+Shift+Q`: ウィンドウを閉じる、`Meta+Ctrl+F`: フルスクリーン
  （`Meta+F`=Float 切替と衝突するため空きキーに配置）
- Overview(`Meta+W`)、クリップボード履歴(`Meta+V`)、アクティビティ(`Meta+A`) 等の
  KDE ネイティブ機能は変更せず維持

### 適用状況（2026-09-27 に D-Bus 経由で適用・実機確認済み）

- Polonium 残留（`Polonium*` 21 アクション）: すべて解除
- `Switch to Desktop 1〜10` = `Meta+1〜0`、`Window to Desktop 1〜10` = `Meta+Shift+1〜0`（＋記号表現、上記）
  （既定所有者だった plasmashell の `activate task manager entry 1〜9` と kwin の
  `view_actual_size`(Meta+0) は解除）
- 仮想デスクトップ数 7 → 10
- Krohnkite の `Meta+H/J/K/L` 系はそのまま（Polonium との二重登録が消えた）

---

## モニタ境界の縦オフセット調整（Monitor Align: 設定ページ ＋ monitoralign-daemon）

**実体は独立リポジトリ `~/Documents/kwin-monitoralign`（GitHub: nagata1634/kwin-monitoralign、MIT）**。
2026-09-27 に dotfiles から分離し、KWin スクリプトとして公開する形にした。`install.sh` の
`EXTERNAL_REPOS` が clone して `./install.sh --link` で symlink 導入する。以下は設計の「なぜ」の記録
（コードの正は向こうのリポジトリ）。

**目的**: 横に並べたモニタの上下のズレ（台座・アームの高さ差で数百px単位で出る）を
合わせ、**境界をまたぐときにカーソルが飛ばない**ようにする。Sway 時代の
`settings-menu.sh`「境界の高さ調整」（+50/-50 で少しずつ動かして目で確認、コミット
`3730858`、正解値は横モニタ `position 0 967`）を KDE で再現したもの。

**構成（3ファイル、すべて dotfiles の symlink）**:
- `home/.local/share/kwin/scripts/monitoralign/`: KWin スクリプトの**器**。`code/main.js`
  は空で、`config/main.xml` と `ui/config.ui` を `kcm_kwin4_genericscripted` に描かせる
  ためだけに存在する。**この2ファイルはデーモンが「いま有効なモニタ」から生成する**
  （`.gitignore` 済み。静的な .ui しか置けない KCM に、接続名 `DP-7　横置き 2560×1440`
  のような行を、繋がっている分だけ出すため）。System Settings › ウィンドウの管理 ›
  KWin スクリプト › Monitor Align の歯車で開き、[適用] で `~/.config/kwinrc` の
  `[Script-monitoralign] y_DP_7=` のように**接続名ごとのキー**に書かれる（抜き差しで
  スロットがずれない）。KPackage の暗黙要件（`code/main.js` と `ui/main.qml` の実在）
  のため両方置いてある
- `home/.local/bin/monitoralign-daemon`: 常駐ヘルパー（PySide6 `QFileSystemWatcher`）。
  kwinrc の変更を検知し、有効な全出力を「内蔵パネル(eDP/LVDS/DSI) → 外部(接続名昇順)」
  の順に**横一列・隙間なし**で並べ、各モニタの Y に接続名ごとの設定値を使って
  `kscreen-doctor output.X.position.x,y ...` を**全出力まとめて1コマンド**で適用する。
  適用後 `kscreen-doctor -j` を読み戻して照合し、不一致なら直前の配置へ自動復帰する。
  10秒ごとに出力集合/配置を確認し、抜き差しで変わったら設定ページを再生成して再適用。
  `--status` で接続名↔現在の配置↔設定値を確認、`--once` で1回適用
- `home/.config/systemd/user/monitoralign.service`: `plasma-workspace.target` 配下で常駐

**なぜこの分担か**: KWin スクリプトには出力を動かす API が無く、設定ダイアログ
（generic KCM）はロジックを持てない。QML 変更はログアウトまで反映されない。
そこで **KWin 側にはコードを一切置かず**（値の器だけ）、動かす処理は KWin の外の
デーモンに置く。デーモンは `systemctl --user restart monitoralign` で即反映できる。

**「間隔が空いてカーソルが隔離される」事故の再発防止（構造的保証）**:
- X はユーザーに設定させず、左隣までの論理幅の合計で毎回計算する（単一出力だけを
  動かす経路が無い）
- Y は最小値を 0 に正規化（`kscreen-doctor` は負座標を静かに拒否する。後述）し、
  隣同士の縦範囲が必ず重なるようクランプする（`layout()` 純関数。クランプ時はログ）
- 座標は **`kscreen-doctor -j` の `pos`（論理座標）と `round(size/scale)`（論理サイズ）
  だけ**を使う。`xrandr` と `×scale` 換算は使わない（下記の真因）

**2026-09-26 に確定した座標系の真実（以前の記述は誤りだった）**:

| 情報源 | DP-7 | DP-8 |
|---|---|---|
| Qt `QScreen.geometry()` | (0, 686) 1969×1108 | (1970, 0) 1108×1969 |
| `kscreen-doctor -j` `pos` / `round(size/scale)` | (0, 686) 1969×1108 | (1970, 0) 1108×1969 |
| `xrandr`（XWayland） | (0, 892) | (2561, 0) |

Qt と kscreen-doctor は同じ **KWin 論理座標**で完全一致する。`xrandr` だけが ×1.3
（scale）の物理px。旧ツール `cursorprobe-adjust` は xrandr を「正」と誤認して Qt の値に
×1.3 した座標を `kscreen-doctor` に渡していたため、2561 を送ると実際は 2561×1.3=3329 に
置かれ、**769px の間隔**が空いてカーソルが隔離された。「kscreen-doctor の `pos` は実配置と
乖離する」という以前の結論は、ログアウト前に無効化した eDP-1 のスロット(1920px)が設定
レイヤーに残っていた一時現象を誤認したもの。`kscreen-doctor -j` の `size` は回転適用済みの
物理px（縦置き DP-8 なら 1440×2560）、`modes[].size` は回転前なので使わない。

**`kscreen-doctor` は負の座標を受け付けない（静かに失敗する）**:
`output.<name>.position.X,-Y` を渡すと `applying config failed! 有効な出力 <name> の位置が
負の値です` と出力するだけで**終了コードは 0**。デーモンは出力文字列の `failed` と
読み戻し照合の両方で検知する。

**運用**: 値は**Primary（`kscreen-doctor -j` の `priority` 最小 = KDE の設定）に対する相対値**（正 = Primary より下）。Primary の行は「基準 — 0 px」で固定し、他のモニタ行のスライダー（粗調整、±モニタ高さ）・[−10][−1][+1][+10] ボタン（.ui の `<connections>` で `QSpinBox.stepUp/stepDown` に直結。±1 は隠しスピンボックス経由）・数値欄（直接入力）で値を決め、[適用] で反映。絶対値だと2枚で2つの数字を持つ冗長さが分かりづらい、というフィードバックで相対値にした。**汎用 KCM は [適用] 以外の契機で何も実行できない**（値変更で即適用、は C++ で KCM を自作しない限り不可）。試した回避策と結末: (1) `QLabel` の`openExternalLinks` リンク `monitoralign:DP-7/-10` を `x-scheme-handler` の .desktop で受けて即適用する方式 → 動作はしたが（systemsettings の PATH に `~/.local/bin` が無く絶対パス必須という罠つき）「リンク方式は嫌」で廃止。(2) Plasma ウィジェット版 → ウィジェット一覧の「アンインストール」がsymlink 先の dotfiles 実体ごと消す罠があり、歯車で足りるため廃止。
境界をまたいでカーソルを横に動かし、飛ばなくなる値で確定。参考: Sway の 967 は論理座標で ≈ 967/1.3 ≈ 744、現在値は 686。
2台の KTC H27T27 は EDID が同一なので接続名順（DP-7 が横・左、DP-8 が縦・右）でしか
識別できず、MST で DP-5/6↔DP-7/8 と揺れても相対順は保たれる。
DP-8 は物理的に90度回転（`Rotation: 8`）。

**旧ツール `cursorprobe-adjust`**（オーバーレイをクリックして境界の対応点を実測し
`kscreen-doctor` コマンドを組み立てる独立 GUI）は 2026-09-26 に廃止（git 履歴に残る）。
実測方式は「どこを基準にクリックするか分からない」「Wayland では `geometry()` が
ドラッグ後に更新されない」等で使い勝手が悪く、結局 Sway 時代と同じ「少しずつ動かして
目で確認」に戻した。

---

## パネルのシステムモニタセンサー（DP-8 下端パネル）

DP-8（スクリーン番号 1）の下端パネルに System Monitor Sensor（`org.kde.plasma.systemmonitor`）を
7つ置いている: Disks / メモリ / CPU / CPU温度 / GPU（円グラフ、中央に使用率または ℃、全体量・
ファン rpm・GPU 温度はホバーのツールチップ = `lowPrioritySensorIds`）、ディスクI/O / ネットワーク
（折れ線）。CPU温度は `rangeAuto=false, 0–100` で円を℃に対応させている。
選定理由: 蓋閉じ・ドック常用の ThinkPad は排熱が弱くサーマルスロットリングが起きやすい
（温度＋ファン）、「固まる」原因は容量ではなく I/O 待ち（ディスクI/O）、Wayland 2画面の
コンポジットは iGPU 負荷（GPU）。センサー ID は KDE 同梱プリセット
`/usr/share/plasma/plasmoids/org.kde.plasma.systemmonitor.*/contents/config/faceproperties` と
同じで、実在は `busctl --user call org.kde.ksystemstats1 /org/kde/ksystemstats1
org.kde.ksystemstats1 sensors as N <id>…`（または `allSensors`）で確認できる。

設定は `~/.config/kde-scripts/panel-sensors.js`（dotfiles、`LINK_FILES`）を
`qdbus-qt6 org.kde.plasmashell /PlasmaShell evaluateScript "$(cat …/panel-sensors.js)"` で流す。
冪等: アプレットは `[Appearance] title` で同定し、無ければ `panel.addWidget()` で末尾に追加する
（applet id に依存しない。並び替えはパネル編集モードのドラッグで）。
**appletsrc を直接編集しない**（plasmashell が終了時に上書きし、確実に反映されない）。
Plasma の scripting API（`panels()` → `p.screen` / `widgets()` / `addWidget()` →
`currentConfigGroup` / `readConfig` / `writeConfig` / `reloadConfig()`）なら即時反映・永続化を
Plasma が担う。

---

## 過去の教訓: KWin スクリプト版 cursorprobe で踏んだ罠（現在は不使用）

以下は上記ツールを Meta+F12 の KWin スクリプトとして実装していた時期に判明した
罠の記録。**今の Monitor Align は KWin 側にコードを置かない器だけなので、この節の問題は再発しない**が、
今後 KWin/Script を自作する機会があれば参考になるので残す。

**症状**: `kwinrc` で `Enabled=true` でも `qdbus-qt6 org.kde.KWin /Scripting
isScriptLoaded <id>` が常に `false`。`kpackagetool6 --type KWin/Script -s <id>` の `Path:`
が空。**dbus 経由の `reconfigure` はエラーすら出さず静かに失敗する**ため長く気づけなかった。

**原因の切り分け方**: `kpackagetool6 --type KWin/Script --install <path>` で正式インストール
を試すと `Error: ... Package is not considered valid` と明示的に出る。ここから
動作実績のある Krohnkite の中身と1ファイルずつ比較して原因を特定した。

**判明した暗黙要件**（`X-Plasma-API: declarativescript` でも例外なく要る）:
1. `contents/code/main.js` の存在（中身は一切使われないダミーで良い）
2. **`X-Plasma-MainScript` で別名を指定しても、`contents/ui/main.qml` という名前の
   ファイル自体が存在しないと無効判定される**

自作 KWin スクリプトは最初からこの2ファイルを用意すること。symlink 配置は原因ではない
（dotfiles からの symlink のままで問題なく動作する）。

**`kpackagetool6 --upgrade` の事故**: この原因切り分け中に `--upgrade <既存パス>` を
実行したところ、**対象（krohnkite）の実体ディレクトリが即座に削除され** `No such file`
で失敗した。内部で一旦既存パッケージを消してから入れ直す実装らしい。実行中の KWin
プロセスはメモリ上にロード済みのままだったため実害はなかったが、`--upgrade` は
正式リリース物（zip の `.kwinscript`）に対してのみ使い、**手動配置/symlink した
ディレクトリに対しては使わない**こと。消えた場合は GitHub 公式リリースから
sha256 照合の上で再インストールする。

**外部との通信手段はほぼ全滅、座標の自動記録は `QtQuick.LocalStorage` のみ動作確認済み**:

- `console.log()` / `print()` → この環境の KWin/declarativescript では **journalctl に
  一切出力されない**（Krohnkite 自身の起動時ログすら journalctl 上に存在しない）。
  ロギングカテゴリのデフォルト設定に起因するとみられるが未解明
- `new XMLHttpRequest()` → **呼んだ瞬間スクリプト全体がクラッシュする**。try-catch で
  囲んでも効かない（OSD 表示すら止まる）。KWin スクリプトのサンドボックスで
  未対応の可能性が高い。**二度と試さないこと**
- `QtQuick.LocalStorage`（SQLite）→ **動作する**。ただし OSD 表示とは別の `Loader`
  に完全に分離し、`try { ... } catch {}` で囲んで呼ぶこと。DB は
  `~/.local/share/kwin/QML/OfflineStorage/Databases/<hash>.sqlite` に作られる
  （ファイル名はハッシュなので、対の `.ini` の `Name=` で検索して特定する）

**KWin は実行中、QML の変更を確実には再読み込みしない（最大の罠）**: `main.qml` の
中身を書き換えても、`unloadScript` → 無効化 → `reconfigure` → 有効化 → `reconfigure`
（`isScriptLoaded` が `false`→`true` と遷移することまで確認しても）、
`kbuildsycoca6 --noincremental`、`metadata.json` の `Version` を上げる、
`~/.cache/kwin/qmlcache/*.qmlc` の削除——**これらをすべて試しても最初にロードした
バージョンのコードが動き続けた**（スクリーンショットで実際の表示内容を確認して確定）。
**唯一効いたのはログアウト→ログイン（KWin プロセスそのものの再起動）だけ**。
コード変更後の動作確認は、`isScriptLoaded` やログではなく**実際の挙動をスクリーンショット
等で目視確認**しないと、古いコードのまま「直った」と誤認する。確実に反映させたいときは
ログアウト→ログインが要ることを前提に計画すること。

---

## 蓋を閉じたときの挙動

**Sway 時代の「ロックを持たない設計」は廃止**。Kinoite では KDE 標準の kscreenlocker を
使う（`powerdevilrc` の `[AC][SuspendAndShutdown] LidAction=64` 等で制御）。

**既知のバグへの対策（稼働中）**: KDE Plasma 6 の kscreenlocker/KWin には、蓋を閉じた状態で
ロック解除すると出力構成が内蔵ディスプレイ(eDP-1)込みでリセットされる既知の不具合がある
（bugs.kde.org #363238, #450757 等と同系統）。`kde-lid-unlock-fix.service`
（`~/.config/kde-scripts/lid-unlock-output-fix.sh`）が `org.freedesktop.ScreenSaver` の
`ActiveChanged(false)` を監視し、アンロック時に蓋が閉じていれば `kscreen-doctor
output.eDP-1.disable` を打ち直す。`enabled`/`active` であることを確認済み。

**未解決**: 3画面（内蔵+外部2枚）の状態から蓋を閉じると、内蔵ディスプレイが消えると
同時に**パネル（タスクバー）も見えなくなる**別の問題がある（上記の内蔵ディスプレイ
復活バグとは別症状）。調査結果:

- パネルの `lastScreen`（`plasma-org.kde.plasma.desktop-appletsrc`）はその時点の
  プライマリディスプレイを指すが、プライマリの判定は蓋の開閉などの topology 変化の
  たびに KWin が再計算しており、`kscreen-doctor` での手動プライマリ変更は一時的
- `lastScreen=-1`（「プライマリに追従」を期待）は**誤り**。実際は「どの画面にも
  表示されない」結果になり plasmashell 再起動が要る。使わないこと
- 外部モニタ2枚は EDID が完全同一かつ MST 接続で `DP-7/DP-8/DP-6` の connector 名が
  セッションを跨ぐたびにドリフトするため、「特定の外部モニタを恒久的に狙う」自動化は
  原理的に不安定
- Plasma 6.3+ の「パネルを複製（Clone Panel）」はこの環境では機能しなかった（原因未調査）

次に試すなら: KWin の output 変化に反応する常駐スクリプト（udev drm subsystem 監視）で
「毎回プライマリを外部へ強制」を継続的に再適用する自動化、または Clone Panel 失敗原因の
深掘り。どちらも未着手。

---

## サスペンドからの復帰源（USB remote wakeup）— DE 非依存

**症状**: サスペンド後、ドックに繋いだキーボードを叩いても復帰しない。

**原因**: USB の remote wakeup は経路上のハブが全て `power/wakeup=enabled` でないと
root controller まで届かない。この機材はハブを3段挟む
（`usb3 (root hub) → 3-1 → 3-1.3 → 3-1.3.2 → REALFORCE`）。

**対処**: `/usr/local/bin/usb-wakeup.sh` + `usb-wakeup.service`（root、`pkexec` で手動設置）。
`pre` で全 USB の wakeup を一旦無効化 → VID:PID から root hub まで親を遡って経路のみ有効化
→ Goodix 指紋リーダー（内蔵、バス停止と同時に切断され誤復帰を起こす）のポートを落として
`/run` に控える。`post` で控えを戻す。identity ベースなので挿すポートが変わっても壊れない。

**post 側の追加処理（2026-09-14）**: 5.5日間の長時間サスペンドから復帰した際、ドック配下
十数台が一斉に再列挙され、外部キーボード無反応・外部ディスプレイ2枚が
「connected/enabled のまま無表示」という状態が発生した。`post` で無条件に
`udevadm trigger --action=change --subsystem-match=usb`（と `drm`）→ `udevadm settle`
を実行するようにして解消した（ドック非接続時も安全な no-op）。

**KVM 切替器を使う場合の罠**: サスペンド突入時に KVM が Windows 側を選択していると、
ドック配下の機器が USB 的に存在せず復帰経路が一切組まれない
（`no USB wake device present; skipping` とログに出る）。対策として、KVM 切替時も
切断されない常設アップリンクハブ（`3-1`、ラップトップ本体側の物理ポート固定）を
`STATIC_UPSTREAM_PORT` として、配下に何も無くても常時 wakeup を有効化する処理を追加した
（KVM を Linux 側へ戻した瞬間の connect イベントを拾う狙い。効果は次回の実運用で要検証）。

`install.sh` は root 操作を行わないので手動設置:

```sh
pkexec install -m 0755 ~/.dotfiles/system/bin/usb-wakeup.sh /usr/local/bin/
pkexec install -m 0644 ~/.dotfiles/system/systemd/usb-wakeup.service /etc/systemd/system/
pkexec sh -c 'systemctl daemon-reload && systemctl enable usb-wakeup.service'
```

---

## Apple Magic Trackpad がログイン直後に反応しない（Sway 時代の知見、Kinoite での再検証は未実施）

**症状**: GUI ログイン後、トラックパッドが操作を受け付けない。電源入れ直すと直る。

**対処（Sway 時代）**: `sway-trackpad-reset.service` が libinput 層で
`events disabled` → 1秒 → `enabled` と入れ直す暫定対処。**Kinoite でこの問題が再現するか、
再現した場合に同じ対処で足りるかは未検証**（ユニット自体は enabled のまま残しているが
is-active は inactive）。libinput 層の話であれば DE に依存しないはずなので対処自体は
流用できる可能性が高い。

USB 層でリセットが要る場合: `<hub_intf>/usbN-portM/disable` に 1→0 と書くとポートごと
落とせる（物理的な電源入れ直しに一番近い）。`authorized=0` は効果が薄い。

---

## キーリング（gnome-keyring）

Sway 時代と方針は同じ。**Bitwarden は Secret Service の代替にならない**
（`gh` のトークン、Brave の暗号化キー、VS Code の認証情報が Secret Service API 経由）。
KDE 標準は KWallet だが、KDE 依存が重くなるため採用せず gnome-keyring を継続している。

**空パスワードにしている理由**: `/var/home` が LUKS で暗号化済みなので二重の暗号化にあたる。
u2f/指紋ログインではパスワードが PAM に渡らず `pam_gnome_keyring` の自動解錠が原理的に
不可能なため、パスワードを外してプロンプトを解消している。

**変更方法**: CLI ではできない。`org.gnome.seahorse.Application`（Flatpak）で
「Default keyring」→ パスワードの変更 → 新パスワードを空欄。

- **VS Code**: `~/.vscode/argv.json` に `"password-store": "gnome-libsecret"` が必須。
- **Brave**: Secret Portal 経由で成功している（起動オプション不要）。

---

## ssh-agent と鍵のパスフレーズ

`ssh-agent.socket`（systemd --user）+ `environment.d/10-ssh-agent.conf` の
`SSH_AUTH_SOCK=/run/user/1000/ssh-agent.socket` で運用。**Kinoite では `~/.profile` を
経由しなくても GUI アプリまで届いている**（`ssh-add -l` が正常応答することを確認済み。
`startplasma-wayland` が systemd --user の環境を直接引き継いでいるとみられる）。
Sway 時代に必須だった `~/.profile` での再読み込みが今も要るかは未検証。

`~/.ssh/config` に `AddKeysToAgent yes`。鍵にパスフレーズを付ける手順:
1. `ssh-keygen -p -f ~/.ssh/github` でパスフレーズを設定
2. 初回接続時に `ssh-askpass` が尋ね、gnome-keyring への保存を選べる
3. 以降はパスフレーズ入力なしで済む（鍵はディスク上で暗号化されたまま）

---

## EDITOR / VISUAL

Sway 時代と同じ。`~/.bashrc.d/60-editor.sh` の1箇所だけで `/etc/profile.d/
nano-default-editor.sh` を上書きする。`VISUAL` は `WAYLAND_DISPLAY` があるときだけ立てる
（Kinoite の Wayland セッションでも `WAYLAND_DISPLAY` は同様に立つはずだが要確認）。

| ツール | 参照順 | GUI 端末 | 素の TTY |
|---|---|---|---|
| `sudoedit` | `SUDO_EDITOR` > `VISUAL` > `EDITOR` | code --wait | nvim |
| `systemctl edit` | `SYSTEMD_EDITOR` > `EDITOR` > `VISUAL` | nvim | nvim |
| `git commit` | `core.editor` が最優先 | code --wait | code --wait |

---

## パッケージとアプリの方針（Fedora Atomic）

**ベースは Fedora Kinoite（KDE Plasma / Wayland）**。Konsole / Dolphin / Kate / Discover /
Firefox / plasmalogin / plasma-* はベースに含まれるため `packages.txt` には書かない。
ベース同梱パッケージの削除（`rpm-ostree override remove`）はアップデート時のリスクがあるため
避け、使わないものは `~/.local/share/applications/` に `NoDisplay=true` の同名 desktop
ファイルを置いて隠す。

**Sericea から Kinoite へ移行したときの差分**: 追加レイヤは `foot` / `kvantum` /
`fcitx5-qt6`。`rofi`・`waybar`・`dunst`・`sway`・`swayidle`・`grim`・`slurp` は Sericea の
*ベース*同梱（層ではなかった）ため、Kinoite では単に存在しなくなった。

- **fcitx5-qt6 が要る理由**: Plasma 6 は Qt6。KRunner で日本語を打つのに要る
- **ログイン**: KDE 標準の plasmalogin（ベース同梱、SDDM は不在）。greetd + tuigreet は
  2026-09-27 に退役（「GUI セッションの環境」参照）。ロックは kscreenlocker。
  pam_u2f は authselect の `system-auth`/`password-auth` 経由で両方に効いている
- **kvantum**: WhiteSur-kde（macOS 風テーマ）が推奨するスタイルエンジン。Qt6 版の
  パッケージ名は導入時に確認すること
- **COSMIC を捨てた経緯**: fcitx5 の不動作が原因だった。DE を変えるときは必ず最初に
  実機で日本語入力（特に KRunner）を確認すること

**2026-09-27 レイヤ最小化（12 → 7）の判断**:

| パッケージ | 判断 | 理由 |
|---|---|---|
| greetd / greetd-selinux / tuigreet | 削除 | plasmalogin（ベース）へ |
| fcitx5-autostart | 削除 | KWin が fcitx5 を起動する構成。autostart は使わない |
| podman-compose | 削除 | 公式 `docker-compose` 静的バイナリを `~/.local/bin` に（`install.sh` の `install_compose`）。`podman compose` の provider になる。VS Code の `dev.containers.dockerComposePath` は GUI の PATH に `~/.local/bin` が無いため絶対パス |
| fcitx5 / fcitx5-mozc | 残す | fcitx5 本体はベースに無い（libs/gtk/qt だけがベース） |
| pam-u2f / pamu2fcfg | 残す | ホスト PAM に必要 |
| intel-media-driver（RPM Fusion、base の libva-intel-media-driver を override） | 残す | Fedora 版はエンコード機能が削られている |
| code | 残す | Flatpak 版は podman/DevContainer に `flatpak-spawn --host` ラッパと設定変更が必須で「標準で繋がる」状態ではない |
| neovim | 残す | 一度は vi/toolbox 案を選んだが実行時に残す判断に変更 |

明示的にレイヤリングしたパッケージだけを `packages.txt` に書く
（`rpm-ostree status --booted` の `requested-packages` が正）。

**Firefox は消さない**: Brave が落ちたときの最後の手段として、プロファイルごと残す。

**Flatpak** は自由に削除できる。`flatpak uninstall --delete-data <id>` を1件ずつ実行し、
最後に `flatpak uninstall --unused` で孤立ランタイムを回収する。

---

## dotfiles の構造

```
~/.dotfiles/
├── install.sh      curl 一発の入口（冪等・curl | bash 対応）
├── packages.txt    rpm-ostree レイヤリング対象
├── fonts.txt       Nerd Fonts の取得対象（フォント本体は含めない = clone を軽く保つ）
├── bootstrap/      OS インストール層（Kickstart）
├── CLAUDE.md       このファイル
└── home/           ~/ にシンボリックリンクされる実体
```

`~/.config/fcitx5` などは `~/.dotfiles/home/.config/fcitx5` への symlink になっている。
つまり**設定を編集すればそのままリポジトリの変更になる**（手動コピーは不要）。
KDE 固有の外観資産（`~/.local/share/color-schemes/Solarized*`、`~/.local/share/plasma/look-and-feel/
dev.yuya.solarized.*`）も同様にファイル単位で `LINK_FILES` に登録して symlink している。
**自作の KDE 拡張のうち公開しているもの（Monitor Align = `nagata1634/kwin-monitoralign`、
Span Image 壁紙 = `nagata1634/plasma-spanimage`、GPL-2.0-or-later）は独立リポジトリ**で、
`install.sh` の `EXTERNAL_REPOS` が `~/Documents/` に clone して各リポジトリの `install.sh --link`
で導入する（開発はそのリポジトリで行い、dotfiles には含めない）。`kwinrc` / `kglobalshortcutsrc` 等の頻繁に
GUI から書き換わる設定ファイル自体は dotfiles 管理下に**入れていない**（意図的な選択）。

**`install.sh` の要点**

- `curl | bash` で動かすため、`packages.txt` を読む前に必ず clone を済ませる
- 同じ理由で `sudo -v < /dev/tty` で事前認証している
- `~/.bash_profile` はマーカー（`# >>> dotfiles: profile >>>`）で `. ~/.profile` の1行を
  冪等に挿入している
- `~/.config/systemd/user/` と `~/.bashrc.d/` は**ファイル単位**でリンクしている
  （ディレクトリごとリンクすると環境固有のユニット/スクリプトが消えるため）

**bash 環境**

`~/.bashrc` は Fedora のデフォルトをそのまま取り込んだもの。本体は末尾の
「`~/.bashrc.d/*` を順に読む」ループ。

| 置き場所 | 用途 |
|---|---|
| `~/.bashrc.d/50-aliases.sh` | エイリアス・関数 |
| `~/.bashrc.d/60-editor.sh` | `EDITOR` / `VISUAL` |
| `~/.bashrc.d/90-tty-locale.sh` | 対話 TTY を `LC_ALL=C.UTF-8` に落とす |
| `~/.bashrc.d/bitwarden.sh` | `bwu`（Bitwarden 解錠）。**dotfiles には含めない**（環境固有のコンテナ依存） |

**公開リポジトリなので機密を入れない**。`.gitignore` で環境固有の秘密情報を除外している。

---

## 旧構成: Sway(Sericea) への切り戻し

`rpm-ostree status` で `sericea` デプロイメントが `Pinned: yes` のまま残っている。
何らかの理由で Kinoite が使えなくなった場合の保険。

- 切り戻し手順: `rpm-ostree status` で sericea の index を確認し
  `rpm-ostree rollback` または `ostree admin deploy` で該当コミットを起動対象にする
  （**破壊的操作なので実行前に必ず現在の作業を確認・確定させること**）
- Sway 側の dotfiles 資産（`config/sway`, `rofi`, `waybar`, `dunst`, `foot`,
  `install.sh --minimal` オプション等）は削除せずそのまま残してある。
  Sericea で起動すれば従来どおり動くはず（Kinoite 移行後は未検証）
- `packages.txt` は Kinoite 前提に書き換え済みのため、Sericea へ切り戻した場合は
  `rofi`/`waybar`/`dunst`/`swayidle`/`grim`/`slurp` 等が「ベース同梱」に戻るので
  問題なし。逆に `foot`/`kvantum`/`fcitx5-qt6` は Sericea では不要だが害もない

**将来の判断が必要な点**: Sericea をいつまで保持するか、Sway 側の dotfiles を
いつメンテナンス対象から外すかは未決定。

---

## 将来の方針

**bootc / OSTree native container**: `Containerfile` でパッケージレイヤリングを OS イメージに
焼き込めば、`rpm-ostree` の逐次レイヤリング（再起動を伴う）が不要になり再構築が高速・再現的になる。
Fedora 44 で利用可能。`packages.txt` を `RUN dnf install` に変換する形にすれば
`install.sh` と定義を共有できる。

**Ignition は使えない**: Fedora CoreOS 専用で Silverblue/Sericea 系では利用できない。
OS インストールの自動化は Kickstart（`bootstrap/`）で行う。
