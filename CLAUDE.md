# 設計ノート

Fedora **Sway Atomic** 上の Sway 環境。各設定ファイルには要点だけを書き、
「なぜそうなっているか」はこのファイルに集約している。設定を変える前にここを読むこと。

- 構成: greetd(tty1) → tuigreet → sway、IME は fcitx5 + Mozc、バーは waybar
- **ロック画面は持たない**（後述「ロックを持たない設計」）
- ランチャー・メニューは rofi、ターミナルは foot、ブラウザは Brave(Flatpak)
- `/var/home` は LUKS 上の btrfs（ディスク全体が暗号化済み）

---

## GUI セッションの環境（`~/.profile`）

**greetd がセッションを起動するコマンドはこれ**（greetd のバイナリに埋め込まれている。
`strings /usr/bin/greetd | grep '\.profile'` で確認できる）:

```sh
[ -f /etc/profile ] && . /etc/profile; [ -f $HOME/.profile ] && . $HOME/.profile; exec sway
```

つまり:

- **`bash -l -c 'exec sway'` ではない**。`~/.bash_profile` は GUI セッションでは**読まれない**
- `/etc/profile` は読まれるので `/etc/profile.d/lang.sh`（CJK → en_US 置換）と
  `nano-default-editor.sh`（`EDITOR=nano`）はそのまま通る
- **sway 配下の全 GUI アプリの環境の起点は `~/.profile` ただ一つ**

**踏んだ落とし穴**: かつてロケールと ssh-agent の設定を `~/.bash_profile` に置いていたため、
**どちらも GUI セッションに効いていなかった**。端末（`.bashrc` 経由）からは効くので気づきにくい。
症状: `locale-audit` が `systemd (user) の LANG が源と違う` を出す、
sway から起動した VS Code が `SSH_AUTH_SOCK` を持たず devcontainer の git 認証が通らない。
確認は `tr '\0' '\n' < /proc/$(pgrep -x swaybg)/environ`（sway 自身の `environ` は
greetd が権限を落として exec するため読めない。その子プロセスを見る）。

`~/.profile` は **`sh` で読まれるので POSIX 記法のみ**（`[[ ]]`・配列・`local` は使えない）。
bash のログインシェルは `~/.bash_profile` があると `~/.profile` を読まないため、
`~/.bash_profile` 側に `. ~/.profile` の1行を `install.sh` がマーカーで挿入している
（`. ~/.bashrc` の**後**であることが要。理由は次節）。

---

## ロケール分離（GUI = 日本語 / TTY = 英語）

**方針**: sway 配下の GUI は日本語、素の VT（`/dev/tty1-6` のテキストコンソール）は英語。

**なぜ VT を英語にするか**: VT はカーネルのコンソールフォント（PSF 形式・最大 512 グリフ）を使い、
fontconfig を一切参照しない。`~/.local/share/fonts` に日本語フォントを入れても VT には届かず、
日本語は原理的に豆腐（□）になる。復旧作業で TTY を使うため読めないと困る。

**踏んだ落とし穴**: `/etc/profile.d/lang.sh` の末尾に、
「`TERM=linux` かつ実 tty のログインシェル」なら CJK ロケールを `en_US.UTF-8` へ強制置換する
コードがある（`ja*`/`ko*`/`zh*` 等が対象）。greetd は `/etc/profile` を読むためこの条件を満たし、
**sway とその配下の全 GUI アプリが `LANG=en_US.UTF-8` を継承する**。
Brave の UI が英語だった原因はこれ。上書きは `~/.profile` で行う（前節）。

特徴的な症状: `LANG` だけ `en_US.UTF-8` で `LC_TIME` 等は `ja_JP.utf8` のまま
（lang.sh は `LANG` のみ書き換えるため）。`/etc/locale.conf`・`localectl`・
`systemctl show-environment`（システム側）は ja_JP なのに、
`systemctl --user show-environment` だけ en_US という形で現れる。

**構成**（`/etc` は一切変更しない）

| ファイル | 役割 |
|---|---|
| `~/.config/locale.env` | **単一の真実の源**。`LANG=ja_JP.UTF-8` / `LANGUAGE=ja` |
| `~/.config/environment.d/90-locale.conf` | 上記への **symlink**（systemd --user が起動時に読む） |
| `~/.profile` のロケールブロック | `lang.sh` の**後**に読まれるので、ここで上書きする。**GUI に効くのはここだけ** |
| `~/.bash_profile` の `dotfiles: profile` ブロック | bash のログインシェル（TTY）に `~/.profile` を読ませるだけ |
| `~/.bashrc.d/90-tty-locale.sh` | 対話 TTY のみ `LC_ALL=C.UTF-8` に落とす（豆腐対策） |
| `sway config.d/30-session-env.conf` | コア。継承値を systemd/D-Bus へ伝播 |
| `sway config.ext.d/31-session-env-locale.conf` → `scripts/sway-env-propagate.sh` | 拡張。`locale.env` の値で上書き |

**順序が要**: `~/.bash_profile` は先頭で `. ~/.bashrc` を読むため、TTY では
`90-tty-locale.sh` が先に `LC_ALL=C.UTF-8` を立てる。その後に読まれる `~/.profile` は
`[ -z "$LC_ALL" ]` ガードでスキップされ、TTY は英語のまま保たれる。
**`. ~/.profile` は必ず `. ~/.bashrc` より後に置くこと。**

**必須のガード**: `90-tty-locale.sh` の `[[ $- == *i* ]]`（対話シェル判定）。
greetd は非対話の `sh` でセッションを起動するので、これが無いと
**GUI セッションまで英語に落ちる**。

**効かない方法**: `~/.config/environment.d/` に `LANG` を書くだけでは効かない。
systemd --user の起動より sway の環境伝播が後になり、そちらが勝つ。

**監査**: `locale-audit`（`~/.local/bin`）で全層の配線を検査できる。`--deep` で Flatpak 内も確認。

**なぜ環境伝播を sway 側で行うか**: systemd --user からは sway の環境（`WAYLAND_DISPLAY`,
`SWAYSOCK`）が見えないため、この橋渡しは sway から実行するしかない。systemd に移せない。

---

## 常駐ツールの起動元マップ

「どこで起動しているか探すのが面倒」を避けるための一覧。**sway config には常駐の起動をほぼ置いていない**。

| ツール | 起動元 | 備考 |
|---|---|---|
| waybar | `systemd --user` : `waybar.service` | `config.d/90-bar.conf` は**システム版を上書きして bar を出さないためだけ**のファイル。ユニットが無いとバーが一切出ない |
| swayidle | `systemd --user` : `swayidle.service`（`ExecStart` に直接記述） | `config.d/90-swayidle.conf` も同様に「exec しない」ための上書き。アクションは `sway-*.service` に切り出してある |
| fcitx5 | `/etc/xdg/autostart/org.fcitx.Fcitx5.desktop`（`fcitx5` パッケージ同梱）→ systemd --user | dotfiles 不要。パッケージを入れれば動く |
| Magic Trackpad の入れ直し | `systemd --user` : `sway-trackpad-reset.service` | ログイン直後に反応しない問題の対処（後述） |
| gnome-keyring | `systemd --user` : `gnome-keyring-daemon.service`（`pkcs11,secrets`） | sway 側では起動しない |
| ssh-agent | `systemd --user` : `ssh-agent.socket` | `SSH_AUTH_SOCK` は `environment.d/10-ssh-agent.conf`（systemd 配下）と `~/.profile`（sway 配下の GUI）の**両方**が要る |
| Gmail / カレンダー PWA | `systemd --user` : `pwa-gmail.service` / `pwa-calendar.service` | **環境固有なので dotfiles には含めない**。作り方は README 参照 |
| 環境変数の伝播 | sway : `config.d/30-session-env.conf` + `config.ext.d/31-session-env-locale.conf` | systemd に移せない（上記の理由） |
| ワークスペース正規化 | sway : `config.ext.d/15-workspace-outputs.conf` の `exec_always` | reload 時も再実行される必要があるため sway 側 |

sway config に残っている `exec` はこの表の最後の 2 つだけ。それ以外は systemd に移してある。

**補足**

- **ロック画面は無い**。次節を参照。
- **PWA は隠れていても通知が届く**。ウィンドウ（プロセス）が動き続けるため dunst 経由で
  デスクトップ通知が来る。`$mod+F1` / `$mod+F2` で引き出す。初回だけ Brave 側で
  Google ログインと通知許可が必要。

---

## ロックを持たない設計（アイドル・離席・蓋）

**なぜロックをやめたか**: gtklock（ext-session-lock）による解除後、セッションが環境の変更に
追従できなかった。復元時に UI が出ない、ロック中に 1画面 ⇄ 2画面 を切り替えると構成が壊れる、
解除後に fcitx5 の text-input 接続が復帰せず IME が死ぬ（専用の保全ユニットまで抱えていた）。
**ロックは「復元を前提とする仕組み」で、そこが壊れている**。そこで
「閉じる＝その作業の終了」に寄せ、戻らないならセッションごと終了して tuigreet に戻す。

トレードオフ: 離席中の画面は暗転しているだけで、誰でも触れる。ディスクは LUKS なので
電源断以降の保護は変わらない。利便性を優先した判断。

### 挙動

```
操作停止 ─5分→ 画面OFF（暗転のみ）＋離席開始を記録 ─15分→ サスペンド(s2idle)
復帰/操作再開 ─┬ 離席3時間未満 → 記録を消して作業継続
               └ 離席3時間以上 → ログアウト → tuigreet
蓋を閉じた ────┬ 外部モニタあり → クラムシェル（eDP-1 を無効化）
               └ 内蔵画面のみ   → ログアウト → tuigreet（その後 logind がサスペンド）
```

離席時間は**実時刻(epoch)の差**で測る。単調時計ではサスペンド中が数えられない。

### unit の連鎖

```
swayidle.service（唯一の常駐）
  ├ timeout 300  → sway-idle-blank.service   （暗転 → sway-away-mark.service）
  ├ resume       → sway-idle-resume.service  （画面ON → sway-away-check.service）
  ├ timeout 900  → systemctl suspend
  ├ before-sleep → sway-sleep-prepare.service（sway-lid-logout → sway-away-mark）
  └ after-resume → sway-away-check.service
sway-logout.service ← ログアウトの唯一の出口（`swaymsg exit`）
```

`sway-logout.service` に **`PartOf=sway-session.target` は付けない**（自分自身を止めることになる）。

### なぜ判定だけスクリプトなのか

systemd に寄せられなかったものだけが `scripts/` に残っている。再検討時に必ず引っかかるので残す:

| | 可否 | 理由 |
|---|---|---|
| アイドル/復帰の検知 | ✗ | Wayland の idle-notify のみ。swayidle が唯一の入口 |
| サスペンド前後の検知 | ✗ | **user manager に `sleep.target` が無い**（systemd 259 で `LoadState=not-found`）。swayidle の `before-sleep`/`after-resume` が唯一の手段 |
| ログアウト動作 | ✗ | logind の `IdleAction=` にログアウトは無い（ignore/poweroff/reboot/halt/kexec/suspend/hibernate/hybrid-sleep/sleep/lock のみ） |
| 離席時間の比較・蓋の判定 | △ | `ExecCondition=` で構造化できるが、比較そのものは述語スクリプト（`away-expired.sh` / `lid-should-logout.py`） |

### なぜ蓋の分岐を `bindswitch` ではなく `before-sleep` に置くか

logind は `HandleLidSwitch=suspend`。クラムシェルが成立しているのは `Docked=true`
（外部モニタあり）かつ `HandleLidSwitchDocked=ignore` だからで、**外部モニタを外すと
蓋を閉じた時点で logind がサスペンドする**。

ここに sway の `bindswitch` からログアウトを重ねると競合するが、
**`After=`/`Before=` では並べられない**——logind のサスペンド判断も sway の bindswitch も
unit ではなく、同じトランザクションに入らないため。順序を確定させる systemd の仕組みは
**inhibitor lock** で、swayidle が常時握っている:

```
swayidle 1000 yuuya 1675 swayidle sleep "Swayidle is preventing sleep" delay
InhibitDelayMaxUSec = 5s
```

`swayidle -w` は `before-sleep` を同期実行するので、**その中の処理はサスペンドより先に
完了することが logind によって保証される**。副産物として `bindswitch --no-warn` による上書き、
`--reload` 誤爆を防ぐガード、unit 2個が不要になり、**sway config には一切手を入れずに済む**
（`config.d/10-outputs.conf` の `output eDP-1 disable` はそのまま）。

`lid-should-logout.py` が logind の `LidClosed` を見るのはこのため。
「有効な出力が1つも無いこと」だけを見ると、`bindswitch` による `eDP-1 disable` が
まだ効いていないタイミングで取りこぼす。

### unit ファイルの罠

- **`%s` は systemd の specifier**。`date +%s` は `date +%%s` と書く。素で書くと
  ファイルに文字列 `%s` が入り、離席時間の計算が常に失敗する
- **`ExecCondition=` が非0で抜けても `ExecStopPost=` は実行される**（man systemd.service に明記）。
  `sway-away-check.service` はこれを使い、ログアウトしてもしなくても記録を必ず消している
- `ExecStart=` の `*` は systemd がグロブしない。`swaymsg "output * power off"` はそのまま届く
- しきい値の一時変更は `systemctl --user edit sway-away-check.service` で
  `Environment=SWAY_AWAY_LIMIT=60` を上書きする

### IME が死んだときの逃げ道

原因は ext-session-lock だったのでサスペンド復帰では起きないはずだが、万一再発したら
`sway-idle-resume.service` に次の1行を足せば済む:

```
ExecStart=/usr/bin/systemctl --user restart app-org.fcitx.Fcitx5@autostart.service
```

---

## サスペンドからの復帰源（USB remote wakeup）

**症状**: サスペンド後、ドックに繋いだキーボードを叩いても復帰しない。蓋を開けるか
内蔵キーボードを叩くしかない。「ログイン画面すら光らない」ように見えるが、
復帰処理自体は正常（`PM: suspend exit` は出る）で、**起こせていないだけ**。

**原因**: USB の remote wakeup は**経路上のハブが全て `power/wakeup=enabled`** でないと
root controller まで届かない。この機材は全機器がドック 1 台にぶら下がっており、

```
usb3 (root hub) → 3-1 → 3-1.3 → 3-1.3.2 → REALFORCE(0853:0311)
```

とハブを 3 段挟む。当初の udev ルールは**末端 HID しか設定していなかった**ため、
キーボード自身が enabled でも信号が上がらなかった。

**切り分けに使った materia**（再発時はこれを見る）

```sh
# 誰が起こしているか。USB が 0 で LID/serio0 だけ増えていれば USB 経路が死んでいる
pkexec awk 'NR==1 || $2+0>0' /sys/kernel/debug/wakeup_sources
# 経路の各段
for h in usb3 3-1 3-1.3 3-1.3.2 3-1.3.2.2; do
  echo "$h $(cat /sys/bus/usb/devices/$h/power/wakeup)"; done
```

PCI 側（`0000:00:14.0`）と ACPI 側（`/proc/acpi/wakeup` の `XHCI`）は元から enabled で、
塞がっていたのはハブ層だけだった。

**もう一段の罠**: ハブ経路を有効にすると、今度は**眠れなくなる**。
**Goodix 指紋リーダー（`3-7`, 27c6:6594。内蔵で root hub 直結）**がバス停止と同時に
切断され、その port status change が root hub の remote wakeup を叩いて
**1〜2 秒で勝手に復帰する**。ポートを落として実測すると 33.8 秒眠り、キーボードで
復帰できた。外れた仮説として iPad（Thunderbolt 側）と Wacom を潰してある。

**対処**: udev ルールは path 依存で挿し替えに弱いため破棄し、
`system/bin/usb-wakeup.sh` ＋ `system/systemd/usb-wakeup.service` に置き換えた。
`pre` で全 USB の wakeup を一旦無効化 → **VID:PID から root hub まで親を遡って**
経路のみ有効化 → Goodix のポートを落として `/run` に控える。`post` で控えを戻す。
identity ベースなので**挿すポートやバス番号が変わっても壊れない**。
ドックを外してノート単体で使うときは経路を張れないので何もせず抜ける
（蓋・内蔵キーボード `serio0`・電源ボタンは platform デバイスなので対象外）。
副作用として USB LAN の Wake-on-LAN が無効になる。

`install.sh` は root 操作を行わないので**手動設置**:

```sh
pkexec install -m 0755 ~/.dotfiles/system/bin/usb-wakeup.sh /usr/local/bin/
pkexec install -m 0644 ~/.dotfiles/system/systemd/usb-wakeup.service /etc/systemd/system/
pkexec sh -c 'systemctl daemon-reload && systemctl enable usb-wakeup.service'
```

---

## Apple Magic Trackpad がログイン直後に反応しない

**症状**: GUI ログイン後、トラックパッドが操作を受け付けない。トラックパッド側の電源を
入れ直すと直る。

**対処**: `sway-trackpad-reset.service`（`sway-session.target` から起動）が libinput 層で
`events disabled` → 1秒 → `enabled` と入れ直す。**まだ暫定の対処**で、これで直らなければ
USB 層のリセットが要る。

**わかっていること**（`system-audit` 相当の採取結果）

- USB 接続（`05ac:0265`、`3-2.2.2`）。**Bluetooth はペアリング済みだが `Connected: no`**
  なので二重接続ではない
- `hid_magicmouse` は**カーネル組み込み**で 4 つの HID 全てにバインドされている
- sway には**同じ identifier で 2 デバイス**見えている（USB の if00 / if01 の両方）。
  そのため `swaymsg input "1452:613:Apple_Inc._Magic_Trackpad" …` は両方に効く
- `type:touchpad` で指定すると**内蔵の ELAN タッチパッドまで巻き込む**ので identifier を明示する

**USB 層でリセットする場合の制約**: `/dev/bus/usb/*` は `root:root` なのでユーザーからは
リセットできない。既存の `scripts/trackpad-usb-reset.sh` は unbind→bind を行い
`/etc/systemd/system-sleep/` に設置してあるが、**これは一度も実行されていない**
（2026-08-30 に判明）。systemd が見るフックディレクトリは `/usr/lib/systemd/system-sleep/`
**だけ**で、`/etc/systemd/system-sleep/` は無視される（`strings /usr/lib/systemd/systemd-sleep`
と man systemd-suspend.service で確認、systemd 259）。よくある誤解。
Atomic では `/usr` に書けないので、**フックではなく unit で `sleep.target` に紐付ける**のが解
（`usb-wakeup.service` を参照）。トラックパッドが直らないのはこれが原因の可能性が高い。

**より強いリセット手段**: unbind→bind より深い「ポートごと落とす」ができる。
`<hub_intf>/usbN-portM/disable` に 1 → 0 と書くとデバイスがバスから消えて再列挙される
（物理的な電源入れ直しに一番近い）。`authorized=0` ではデバイスがバスに残るので効果が薄い。

**再現したときに採るもの**

```sh
swaymsg -t get_inputs | grep -A5 Magic
journalctl -b -g magicmouse
libinput debug-events --device /dev/input/event17   # 指を動かして反応があるか
systemctl --user start sway-trackpad-reset.service  # これで直るか
```

最後で直るなら libinput 層の話（今の対処で足りる）。直らないなら USB 層。

---

## 操作履歴（`journalctl -t sway-menu`）

メニュー系スクリプトは全て `scripts/lib/rofi.py` の `dmenu()` を経由するので、
そこに `syslog` を1箇所仕込んで**「どのメニューを開いたか」と「何を選んだか」**を残している。
`confirm()` も `dmenu()` 経由なので確認ダイアログの応答も残る。
rofi を経由しない `toggle-monitors.py` だけは同じ tag で自前に記録している。

```
sway-menu: power-menu.py → サスペンド
sway-menu: power-menu.py → (キャンセル)
```

**`password=True` の入力内容は記録しない**（`(パスワード入力)` に置き換える）。

**なぜキーバインドを unit 化しないか**: 一時は `sway-bind@.service` テンプレートで
`bindsym` を包む案を採ったが、残るのは「起動した」という事実だけで、上の syslog 行に含意される。
一方で `Type=oneshot` の同一 unit は同時実行できず**ジョブがキューイングされて待たされる**ため、
連打する系（ワークスペース切替・輝度）では体感が悪化する。得るものより失うものが大きい。

---

## EDITOR / VISUAL

`/etc/profile.d/nano-default-editor.sh` が `EDITOR=/usr/bin/nano` を立てるので上書きする。
置き場所は **`~/.bashrc.d/60-editor.sh` の1箇所だけ**。

**なぜ `~/.profile` でも `environment.d` でもないか**: Fedora の `/etc/bashrc` は
**非ログインシェルに対して `/etc/profile.d/*` を読み直す**ため、`~/.profile` に書いても
端末を開いた時点で nano に戻される。`~/.bashrc.d` はその後に読まれるので、ここが唯一勝てる場所。
そして `EDITOR`/`VISUAL` を実際に使うのは端末から起動するコマンド（`sudoedit`・
`systemctl edit`・`git`）なので、1箇所で足りる。二重に置くと値がズレる余地を作るだけになる。

**ツールごとに参照順が逆**なので結果が食い違う:

| ツール | 参照順 | GUI 端末 | 素の TTY |
|---|---|---|---|
| `sudoedit` | `SUDO_EDITOR` > `VISUAL` > `EDITOR` | code --wait | nvim |
| `systemctl edit` | `SYSTEMD_EDITOR` > `EDITOR` > `VISUAL` | nvim | nvim |
| `git commit` | `core.editor` が最優先 | code --wait | code --wait |

`VISUAL` は `WAYLAND_DISPLAY` があるときだけ立てる。素の TTY で VSCode は起動できず、
復旧作業中に git や sudoedit がエディタを開けなくなるため。
git は `core.editor = code --wait` が設定済みで、TTY で困る場合は `GIT_EDITOR=nvim git commit`。

**環境変数の全面一元化は未着手**: `environment.d` を唯一の宣言場所にして bash 側から
機械的に読む構想は筋が良いが、ロケール分離の繊細な仕組みを触ることになる。
`~/.profile` の新設がその第一歩。

---

## sway config のコア / 拡張分離

**目的**: 自作スクリプト群を切り離し、素の sway でも起動・操作できる状態を保つ。

```
~/.config/sway/
├── config          コア。自作スクリプト非依存（$term は foot、$mod+d は rofi）
├── config.d/       コア。素の Sway でも動く設定
├── config.ext.d/   拡張。scripts/ に依存する設定（これが無くても Sway は起動する）
└── scripts/        自作ツール群（1 ファイル 1 目的。共通処理は scripts/lib/）
```

`config` 末尾で 2 段階に include する。`layered-include` は**マッチしないパスを黙って無視**するので、
拡張を入れていない環境でも swaynag は出ない。

`install.sh --minimal` を使うと `config.ext.d` と `scripts` をリンクしないので、
素の Sway 構成で起動できる。

**config.d に残さなければならないファイル**: システム版（`/usr/share/sway/config.d/`）と
**同名のファイルは上書き目的**なので `config.ext.d` に移してはいけない。移すと上書きが効かず、
例えば swayidle が二重起動する。該当: `60-bindings-brightness` `60-bindings-screenshot`
`65-mode-passthrough` `90-bar` `90-swayidle`。

このうち `60-bindings-brightness.conf` だけは `scripts/brightness.py` に実依存があるため、
`--minimal` 環境では輝度バインドの exec が失敗する（sway の起動と基本操作には影響しない）。

**短文化の原則**: config には `exec <command>` / `bindsym <key> exec <command>` の短文だけを書き、
シェルロジック（`&&`・`eval`・`$(...)`・パイプ）は書かない。実装は `scripts/` の小さなツールに置く。
`set $scripts $HOME/.config/sway/scripts` を定義してあるので `exec $scripts/foo.py` と書ける。
各スクリプトには shebang と実行ビットを付けてあるので `python3` の明示は不要。

**変数は定義時に展開される**: sway の変数は使用時ではなく**定義時**に展開される。
そのため `config.ext.d/05-term.conf` で `set $term` を変えても、コア側で既に
`bindsym $mod+Return exec $term` として展開済みのバインドには反映されない。
拡張側で明示的に再定義している。

**bindsym の上書きには `--no-warn` が必須**: 既存バインドを上書きすると swaynag がエラーを出す。
`bindsym --no-warn $mod+Return ...` のように書く。
**`sway -C` と `swaymsg reload` はこの重複を検知しない**ので、変更後は実際に reload して
`pgrep swaynag` で確認すること。

**`keybind-rofi.py` の依存**: `swaymsg -t get_config` は include を展開しないため、
このスクリプトは `CONFIG_D_DIRS` を自前で走査して `#: 機能名` コメントを集めている。
**config.d を増やしたら `CONFIG_D_DIRS` にも追加する**こと（`config.ext.d` は追加済み）。

---

## ランチャーは rofi（fuzzel を捨てた理由）

fuzzel は Wayland ネイティブだが **IME 非対応で日本語変換入力ができない**。
日本語を打つピッカーは rofi（XIM 経由で変換できる）を使う。foot も入力可。
以前は fuzzel を併用していたが、設定ごと削除した。

---

## キーリング（gnome-keyring）

**Bitwarden は代替にならない**。役割が違う。

| | 役割 | 利用者 |
|---|---|---|
| Bitwarden | 人間が使うパスワード管理 | 自分 |
| gnome-keyring | Secret Service API (`org.freedesktop.secrets`) の実装 | `gh` のトークン、Brave の暗号化キー、VS Code の認証情報 |

Bitwarden は Secret Service プロバイダを実装していないため、置き換えると gh・Brave・VS Code の
認証が平文保存に落ちる。KWallet は KDE 依存が重く、KeePassXC は Bitwarden と二重管理になり、
`pass-secret-service` は非公式実装。**PAM 自動解錠に対応しているのは gnome-keyring だけ**。

**空パスワードにしている理由**: `/var/home` が LUKS で暗号化済みなので、キーリング自体の
パスワードは二重の暗号化にあたる。かつ u2f/指紋ログインではパスワードが PAM に渡らないため
`pam_gnome_keyring` による自動解錠が原理的に不可能で、毎回プロンプトが出ていた。
LUKS を前提にキーリングのパスワードを外し、プロンプトを解消している。

**トレードオフ**: ログイン中の同一ユーザープロセスからキーリングが読める。ただしこれは
元々読める範囲であり、ディスクを持ち出された場合の保護は LUKS が担う。

**変更方法**: CLI ではできない（現在のパスワード入力を伴うため）。
`org.gnome.seahorse.Application`（Flatpak）で「Default keyring」を右クリック →
パスワードの変更 → 新パスワードを空欄。

### Secret Service を使うアプリ

- **VS Code**: `~/.vscode/argv.json` に `"password-store": "gnome-libsecret"` が**必須**。
  sway では `XDG_CURRENT_DESKTOP=sway` のため Electron の自動検出が `basic`（平文）に落ち、
  「認証情報を平文で保存します」と警告が出る。dotfiles に含めてあるので別 PC でも再発しない。
- **Brave**: `Local State` の `"os_crypt":{"portal":{...,"prev_init_success":true}}` の通り
  Secret Portal 経由で成功している。起動オプションの指定は不要。

---

## ssh-agent と鍵のパスフレーズ

`ssh-agent.socket`（systemd --user）+ `environment.d/10-ssh-agent.conf` の
`SSH_AUTH_SOCK=/run/user/1000/ssh-agent.socket` で運用する。この値は
`ssh-agent.socket` の `ListenStream=%t/ssh-agent.socket` と一致している。

**過去にハマった点**: env ファイルだけ作って `ssh-agent.socket` を `enable` していなかったため、
`SSH_AUTH_SOCK` が存在しないソケットを指し、`ssh-add -l` が接続失敗していた。
**socket の有効化を忘れないこと**。

**`environment.d` だけでは GUI アプリに届かない**（ロケール分離と同じ構造）。`environment.d` は
systemd --user 配下にしか効かず、`greetd` → `sh` → `sway` → GUI アプリの経路には
伝わらない。そのため `~/.profile` で `environment.d/10-ssh-agent.conf` を読み直している
（値の単一の真実の源は同ファイル。二重定義しない）。

特徴的な症状: **ターミナルからは `ssh` が通るのに、VS Code の devcontainer から `git push` すると
`Permission denied (publickey)`**。コンテナ内の `ssh-add -l` は
`Could not open a connection to your authentication agent` を返す。foot 等のターミナルは
`.bashrc` 経由で環境を作り直すので気付きにくい。Dev Containers は「ホストの `SSH_AUTH_SOCK` を
検出してコンテナへ転送する」仕組みなので、**VS Code 自体が持っていないと転送も起きない**。

**これを `~/.bash_profile` に置いていた頃は効いていなかった**。greetd が読むのは
`~/.profile` であって `~/.bash_profile` ではないため（「GUI セッションの環境」の節を参照）。

`/proc/$(pgrep -f '/usr/share/code/code' | head -1)/environ` を見れば、VS Code が
受け取っているか直接確認できる。**VS Code の再起動では直らない**（sway から起動する限り同じ）。
`devcontainer.json` にソケットのパスを直書きする回避策は、Windows と共用するリポジトリでは
マウントに失敗して壊れるため採らない。

`~/.ssh/config` に `AddKeysToAgent yes` を入れてある。鍵にパスフレーズを付ける手順:

1. `ssh-keygen -p -f ~/.ssh/github` でパスフレーズを設定
2. 初回接続時に `ssh-askpass` が尋ね、gnome-keyring への保存を選べる
3. キーリングが空パスワードで自動解錠されるので、**以降はパスフレーズ入力なしで済む**
   （鍵はディスク上で暗号化されたまま）

`~/.ssh/config` 自体は鍵パスなど環境固有・機密情報を含むため dotfiles には含めない。

---

## パッケージとアプリの方針（Fedora Atomic）

**ベースイメージ同梱パッケージは削除しない**。`rpm-ostree override remove` が必要で、
アップデート時に問題が起きやすい。`firefox`・`Thunar`・`xfce4-panel`・`rofi`・`waybar`・
`dunst`・`foot`・`swaylock`・`ibus` などがこれに該当する。使わないものは
`~/.local/share/applications/` に `NoDisplay=true` の同名 desktop ファイルを置いて隠す。

明示的にレイヤリングしたパッケージだけを `packages.txt` に書く
（`rpm-ostree status --booted` の `requested-packages` が正）。

**Firefox は消さない**: Brave が落ちたときの最後の手段として、プロファイルごと残す。

**Flatpak** は自由に削除できる。`flatpak uninstall --delete-data <id>` を 1 件ずつ実行し、
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

`~/.config/sway` などは `~/.dotfiles/home/.config/sway` への symlink になっている。
つまり**設定を編集すればそのままリポジトリの変更になる**（手動コピーは不要）。

**`install.sh` の要点**

- `curl | bash` で動かすため、`packages.txt` を読む前に必ず clone を済ませる
  （`$BASH_SOURCE` がパイプ実行では使えないため、スクリプトと同階層のファイルは読めない）。
- 同じ理由で stdin がパイプになり `sudo` がパスワードを読めないので、`sudo -v < /dev/tty` で
  事前認証している。
- `~/.bash_profile` は既存ファイルへの追記なので symlink できない。マーカー
  （`# >>> dotfiles: profile >>>`）で `. ~/.profile` の1行を冪等に挿入している。
  旧マーカー（`dotfiles: GUI locale` / `dotfiles: ssh-agent`）が残っていれば撤去する
  移行処理も入れてある（中身は `~/.profile` に移設済み）。
- `~/.config/systemd/user/` はディレクトリごと symlink すると環境固有のユニット
  （`qnap-tpbk.service` など）が消えるため、**ファイル単位**でリンクしている。
  `~/.bashrc.d/` も同じ理由でファイル単位（後述の `bitwarden.sh` を残すため）。

**bash 環境**

`~/.bashrc` は Fedora のデフォルトをそのまま取り込んだもの。本体は末尾の
「`~/.bashrc.d/*` を順に読む」ループで、設定の追加はこのディレクトリへのドロップインで行う。
`oh-my-bash` のようなフレームワークは使っておらず、プロンプトも `/etc/bashrc` 由来のまま。
`[ -f /etc/bashrc ]` のガードがあるので、`/etc/bashrc` を持たないディストリでも壊れない。

| 置き場所 | 用途 |
|---|---|
| `~/.bashrc.d/50-aliases.sh` | エイリアス・関数。**dotfiles 管理下**なので書けば追随する |
| `~/.bashrc.d/60-editor.sh` | `EDITOR` / `VISUAL`（`/etc/profile.d/nano-default-editor.sh` の上書き） |
| `~/.bashrc.d/90-tty-locale.sh` | 対話 TTY を `LC_ALL=C.UTF-8` に落とす（ロケール分離） |
| `~/.bashrc.d/bitwarden.sh` | `bwu`（Bitwarden 解錠）。**dotfiles には含めない** |

`bitwarden.sh` を除外しているのは `toolbox run --container bitwarden-cli` に依存し、
そのコンテナが無い環境では意味を成さないため。同じ理由で環境固有の関数は dotfiles に入れず、
`~/.bashrc.d/` へ直接置く。

**公開リポジトリなので機密を入れない**。`pika-repoint.py` は NAS の内部 IP を
ハードコードしているため `.gitignore` で除外している（sway config からは未参照）。

---

## 将来の方針

**bootc / OSTree native container**: `Containerfile` でパッケージレイヤリングを OS イメージに
焼き込めば、`rpm-ostree` の逐次レイヤリング（再起動を伴う）が不要になり再構築が高速・再現的になる。
Fedora 44 で利用可能。`packages.txt` を `RUN dnf install` に変換する形にすれば
`install.sh` と定義を共有できる。

**Ignition は使えない**: Fedora CoreOS 専用で Silverblue/Sericea 系では利用できない。
OS インストールの自動化は Kickstart（`bootstrap/`）で行う。
