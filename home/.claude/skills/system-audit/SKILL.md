---
name: system-audit
description: この環境（Fedora Sway Atomic / greetd + sway + systemd --user + dotfiles）のシステム設定を全レイヤ横断で棚卸しする。sway・systemd ユーザーユニット・logind・greetd・ロケール・環境変数・rpm-ostree の状態・dotfiles の symlink を一度に集め、どこに何が設定されているかを確定させる。システム設定を変更する作業に入る前、原因が層をまたいで見えないとき、変更後に副作用が無いか確かめるときに使う。
---

# システム設定の全レイヤ監査

この環境は設定が**5つの層**に分かれており、1つの症状の原因が別の層にあることが多い
（例: GUI が英語になる真因が `/etc/profile.d/lang.sh`、IME が死ぬ真因が ext-session-lock）。
**一部だけ見て変更に入らない。** 実装前にこのスキルで全体を確定させる。

設計判断の「なぜ」は `~/.dotfiles/CLAUDE.md` に集約されている。**必ず併せて読む。**

## 層の地図

| 層 | 実体 | 変更していい場所 |
|---|---|---|
| OS イメージ | rpm-ostree deployment / kargs / layered packages | `rpm-ostree install` のみ。差分は最小に |
| システム設定 | `/etc`（greetd・logind・profile.d） | **触らない**（アップグレード時に 3-way merge される） |
| ユーザー常駐 | `systemd --user` の unit / socket | `~/.dotfiles/home/.config/systemd/user/` |
| GUI セッション | sway の `config` / `config.d` / `config.ext.d` / `scripts` | `~/.dotfiles/home/.config/sway/` |
| シェル環境 | `~/.bash_profile` / `~/.bashrc.d/` / `~/.config/environment.d/` | dotfiles 配下 |

## 収集

必要な層だけ選んで実行する。全部走らせても数秒で終わる。

### 1. OS イメージ層

```bash
rpm-ostree status
rpm-ostree kargs
```

見るところ: booted deployment、`LayeredPackages`（＝原型からの差分）、`LocalPackages`、
`consoleblank` や `rd.luks.*` などの karg。

### 2. systemd --user 層

```bash
systemctl --user list-units --no-pager --type=service --type=socket --type=target
systemctl --user list-unit-files --no-pager | grep -v '^ *$'
systemctl --user show-environment
systemctl --user list-timers --all --no-pager
```

見るところ: **どの常駐がどのユニットから起動しているか**、`show-environment` に
`SWAYSOCK`/`WAYLAND_DISPLAY` が伝播しているか（sway 側の `30-session-env.conf` が効いた証拠）。

**落とし穴**: user manager には `sleep.target` / `suspend.target` が**存在しない**。
サスペンド前後のフックをユーザーユニットで受けることはできない（swayidle 経由が唯一の手段）。

### 3. ログイン・電源層

```bash
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager HandleLidSwitch IdleAction IdleActionUSec
loginctl list-sessions
systemctl cat greetd@.service | head -20
ls /etc/greetd/ && cat /etc/greetd/config-tty1.toml
```

見るところ: 蓋・アイドル時の挙動、**セッションが二重になっていないか**、greeter の起動コマンド。

**落とし穴**: logind の `IdleAction=` に「ログアウト」は無い
（ignore/poweroff/reboot/halt/kexec/suspend/hibernate/hybrid-sleep/sleep/lock のみ）。

### 4. sway 層

```bash
ls ~/.config/sway/config.d/ ~/.config/sway/config.ext.d/ ~/.config/sway/scripts/
grep -rn -E '^\s*(exec|exec_always|bindswitch)' ~/.config/sway/config ~/.config/sway/config.d/ ~/.config/sway/config.ext.d/
swaymsg -t get_outputs | python3 -c 'import json,sys; [print(o["name"], o["active"], o.get("transform")) for o in json.load(sys.stdin)]'
pgrep swaynag && echo "!!! swaynag が出ている = config にエラーか bindsym 重複"
```

見るところ: **sway に残っている `exec` は何か**（常駐は systemd に寄せてある。残っているものには
移せない理由がある）、`config.d` の同名ファイルによるシステム版の上書き。

**落とし穴**: 既存 `bindsym`/`bindswitch` の上書きには `--no-warn` が必須。
`sway -C` と `swaymsg reload` はこの重複を検知しないので、`pgrep swaynag` で確かめる。

### 5. シェル・環境変数層

```bash
echo "EDITOR=$EDITOR VISUAL=$VISUAL LANG=$LANG"
ls ~/.bashrc.d/ ~/.config/environment.d/
grep -rn -E '\b(EDITOR|VISUAL|LANG|LC_ALL|SSH_AUTH_SOCK)=' ~/.bashrc ~/.bash_profile ~/.bashrc.d/ ~/.config/environment.d/ 2>/dev/null
grep -rln -E '\b(EDITOR|VISUAL|LANG)=' /etc/profile.d/
locale-audit   # ロケール専用の監査ツール（--deep で Flatpak 内も見る）
```

見るところ: 同じ変数が**何箇所で宣言されているか**と、**読まれる順序**
（`/etc/profile.d/*` → `~/.bash_profile` → `~/.bashrc` → `~/.bashrc.d/*` の順で後勝ち）。

**落とし穴**: `~/.config/environment.d/` は systemd --user 配下にしか効かない。
`greetd → bash -l -c 'exec sway' → GUI アプリ` の経路には伝わらないため、両方に要る変数がある
（`SSH_AUTH_SOCK` がその例）。逆に、端末から使うだけの変数は `~/.bashrc.d/` だけで足りる。

### 6. dotfiles 層

```bash
cd ~/.dotfiles && git status --short && git log --oneline -3
ls -ld ~/.config/sway ~/.config/environment.d
ls -la ~/.config/systemd/user/ | grep '\->'
grep -n -A15 'LINK_FILES=\|LINK_DIRS=\|ENABLE_UNITS=' ~/.dotfiles/install.sh
```

見るところ: **どれがディレクトリ symlink でどれがファイル単位か**。
`~/.config/sway` はディレクトリ symlink なので dotfiles を編集すれば即反映。
`~/.config/systemd/user/` と `~/.bashrc.d/` はファイル単位なので、**新規ファイルは
`install.sh` の `LINK_FILES` に追加しないとリンクされない**。

## まとめ方

集めたら、変更対象について次を明示してから実装に入る。

1. **今どこで設定されているか**（層とファイル名）
2. **変更をどの層で行うか**、そしてなぜその層か（`/etc` を避ける・deployment を汚さない）
3. **その層で表現できないもの**は何で、なぜスクリプトやフックに落ちるのか
4. **副作用の範囲**（同じキー/変数/ユニットを触る別の設定はあるか）
