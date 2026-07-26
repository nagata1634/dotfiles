# 設計ノート

Fedora **Sway Atomic** 上の Sway 環境。各設定ファイルには要点だけを書き、
「なぜそうなっているか」はこのファイルに集約している。設定を変える前にここを読むこと。

- 構成: greetd(tty1) → tuigreet → sway、IME は fcitx5 + Mozc、ロックは gtklock、バーは waybar
- ランチャー・メニューは rofi、ターミナルは foot、ブラウザは Brave(Flatpak)
- `/var/home` は LUKS 上の btrfs（ディスク全体が暗号化済み）

---

## ロケール分離（GUI = 日本語 / TTY = 英語）

**方針**: sway 配下の GUI は日本語、素の VT（`/dev/tty1-6` のテキストコンソール）は英語。

**なぜ VT を英語にするか**: VT はカーネルのコンソールフォント（PSF 形式・最大 512 グリフ）を使い、
fontconfig を一切参照しない。`~/.local/share/fonts` に日本語フォントを入れても VT には届かず、
日本語は原理的に豆腐（□）になる。復旧作業で TTY を使うため読めないと困る。

**踏んだ落とし穴**: `/etc/profile.d/lang.sh` の末尾に、
「`TERM=linux` かつ実 tty のログインシェル」なら CJK ロケールを `en_US.UTF-8` へ強制置換する
コードがある（`ja*`/`ko*`/`zh*` 等が対象）。greetd はセッションを `bash -l -c 'exec sway'` で
起動するためこの条件を満たし、**sway とその配下の全 GUI アプリが `LANG=en_US.UTF-8` を継承する**。
Brave の UI が英語だった原因はこれ。

特徴的な症状: `LANG` だけ `en_US.UTF-8` で `LC_TIME` 等は `ja_JP.utf8` のまま
（lang.sh は `LANG` のみ書き換えるため）。`/etc/locale.conf`・`localectl`・
`systemctl show-environment`（システム側）は ja_JP なのに、
`systemctl --user show-environment` だけ en_US という形で現れる。

**構成**（`/etc` は一切変更しない）

| ファイル | 役割 |
|---|---|
| `~/.config/locale.env` | **単一の真実の源**。`LANG=ja_JP.UTF-8` / `LANGUAGE=ja` |
| `~/.config/environment.d/90-locale.conf` | 上記への **symlink**（systemd --user が起動時に読む） |
| `~/.bash_profile` の `dotfiles: GUI locale` ブロック | `lang.sh` の**後**に読まれるので、ここで上書きする |
| `~/.bashrc.d/90-tty-locale.sh` | 対話 TTY のみ `LC_ALL=C.UTF-8` に落とす（豆腐対策） |
| `sway config.d/30-session-env.conf` | コア。継承値を systemd/D-Bus へ伝播 |
| `sway config.ext.d/31-session-env-locale.conf` → `scripts/sway-env-propagate.sh` | 拡張。`locale.env` の値で上書き |

**順序が要**: `~/.bash_profile` は先頭で `. ~/.bashrc` を読むため、TTY では
`90-tty-locale.sh` が先に `LC_ALL=C.UTF-8` を立てる。その後のロケールブロックは
`[ -z "$LC_ALL" ]` ガードでスキップされ、TTY は英語のまま保たれる。

**必須のガード**: `90-tty-locale.sh` の `[[ $- == *i* ]]`（対話シェル判定）。
greetd は `bash -l -c`（非対話）でセッションを起動するので、これが無いと
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
| swayidle / gtklock | `systemd --user` : `swayidle.service` → `scripts/swayidle-run.sh` | `config.d/90-swayidle.conf` も同様に「exec しない」ための上書き |
| fcitx5 | `/etc/xdg/autostart/org.fcitx.Fcitx5.desktop`（`fcitx5` パッケージ同梱）→ systemd --user | dotfiles 不要。パッケージを入れれば動く |
| fcitx5 の再起動 | `systemd --user` : `fcitx5-relock-watch.service` | gtklock 解除後に IME が死ぬ問題の対処 |
| gnome-keyring | `systemd --user` : `gnome-keyring-daemon.service`（`pkcs11,secrets`） | sway 側では起動しない |
| ssh-agent | `systemd --user` : `ssh-agent.socket` | `SSH_AUTH_SOCK` は `environment.d/10-ssh-agent.conf`（systemd 配下）と `~/.bash_profile`（sway 配下の GUI）の**両方**が要る |
| Gmail / カレンダー PWA | `systemd --user` : `pwa-gmail.service` / `pwa-calendar.service` | **環境固有なので dotfiles には含めない**。作り方は README 参照 |
| 環境変数の伝播 | sway : `config.d/30-session-env.conf` + `config.ext.d/31-session-env-locale.conf` | systemd に移せない（上記の理由） |
| ワークスペース正規化 | sway : `config.ext.d/15-workspace-outputs.conf` の `exec_always` | reload 時も再実行される必要があるため sway 側 |

sway config に残っている `exec` はこの表の最後の 2 つだけ。それ以外は systemd に移してある。

**補足**

- **ロックは gtklock**（swaylock から移行）。`swayidle-run.sh` は `gtklock -d` を使う。
  これは「ロックしてから daemon 化する」挙動で、ext-session-lock プロトコルなので
  **サスペンド前に確実にロックされる**。
- **gtklock 解除後に fcitx5 が死ぬ**問題があり、`fcitx5-relock-watch.service` が
  ロック解除を検知して fcitx5 を restart している。
- **PWA は隠れていても通知が届く**。ウィンドウ（プロセス）が動き続けるため dunst 経由で
  デスクトップ通知が来る。`$mod+F1` / `$mod+F2` で引き出す。初回だけ Brave 側で
  Google ログインと通知許可が必要。

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
systemd --user 配下にしか効かず、`greetd` → `bash -l -c 'exec sway'` → GUI アプリの経路には
伝わらない。そのため `~/.bash_profile` の `dotfiles: ssh-agent` ブロックで
`environment.d/10-ssh-agent.conf` を読み直している（値の単一の真実の源は同ファイル。二重定義しない）。

特徴的な症状: **ターミナルからは `ssh` が通るのに、VS Code の devcontainer から `git push` すると
`Permission denied (publickey)`**。コンテナ内の `ssh-add -l` は
`Could not open a connection to your authentication agent` を返す。foot 等のターミナルは
`.bash_profile` を読むので気付きにくい。Dev Containers は「ホストの `SSH_AUTH_SOCK` を検出して
コンテナへ転送する」仕組みなので、**VS Code 自体が持っていないと転送も起きない**。

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
  （`# >>> dotfiles: GUI locale >>>` と `# >>> dotfiles: ssh-agent >>>`）で冪等に挿入している。
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
