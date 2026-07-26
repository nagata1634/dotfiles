# dotfiles

**Fedora Sway Atomic (Sericea)** 向けの Sway デスクトップ環境一式。
Catppuccin Mocha で配色を統一した Wayland ネイティブ構成で、新しいマシンで 1 コマンド実行すれば
同じ見た目・同じキー操作・同じ日本語入力環境が再現される。

![wm: sway](https://img.shields.io/badge/wm-sway-89b4fa) ![distro: Fedora Atomic](https://img.shields.io/badge/distro-Fedora%20Atomic-cba6f7)

## インストール

```sh
curl -fsSL https://raw.githubusercontent.com/nagata1634/dotfiles/main/install.sh | bash
```

冪等なので再実行しても安全。以下が行われる。

1. `~/.dotfiles` に clone / pull
2. `packages.txt` を `rpm-ostree` でレイヤリング（不足分のみ・要再起動）
3. `fonts.txt` の Nerd Font を `~/.local/share/fonts` へ導入
4. `home/` 配下を `~/` にシンボリックリンク（既存実体はタイムスタンプ付きで退避）
5. `~/.bash_profile` にロケール読み込みブロックを挿入
6. 保全系 `systemd --user` ユニットを有効化

### オプション

| オプション | 用途 |
|---|---|
| `--minimal` | 自作スクリプト群をリンクしない**素の Sway 構成**。`config.ext.d` と `scripts` を除外する |
| `--skip-packages` | `rpm-ostree` のレイヤリングを行わない（検証用） |
| `--skip-fonts` | フォント導入を行わない |

## 主なキーバインド

| キー | 機能 | 素の Sway でも動く |
|---|---|---|
| `Super+Return` | ターミナル（foot） | ✓ |
| `Super+d` | アプリランチャー（rofi・日本語検索可） | ✓ |
| `Super+Shift+q` | ウィンドウを閉じる | ✓ |
| `Super+Tab` | ウィンドウ切替（同一WS内・rofi） | |
| `Super+Shift+Tab` | ワークスペース切替（rofi） | |
| `Super+Shift+/` | キーバインド一覧（`#:` コメントから生成） | |
| `Super+x` | 電源メニュー | |
| `Super+Ctrl+s` | 設定ハブ（WiFi/BT/音/明るさ/画面/通知） | |
| `Super+Shift+n` | 通知センター | |
| `` Super+` `` | スクラッチパッド一覧表示 | |
| `Super+Ctrl+Alt+Escape` | モニタの横/縦の役割を入れ替え | |

「素の Sway でも動く」列が空のものは自作スクリプト依存（`--minimal` では無効）。

## 含まれるもの

| パス | 役割 |
|---|---|
| `home/.config/sway/config`, `config.d/` | Sway 本体。**自作スクリプトに依存しないコア** |
| `home/.config/sway/config.ext.d/` | 自作スクリプト依存の拡張設定（無くても Sway は起動する） |
| `home/.config/sway/scripts/` | 自作ツール群（1 ファイル 1 目的。共通処理は `scripts/lib/`） |
| `home/.config/rofi/` | ランチャー・各種メニュー（Catppuccin Mocha） |
| `home/.config/waybar/`, `dunst/`, `foot/` | バー / 通知 / ターミナル |
| `home/.config/fcitx5/` | 日本語入力（Mozc の学習履歴・個人辞書は含まない） |
| `home/.config/environment.d/`, `locale.env` | ロケールと IME の環境変数 |
| `home/.config/systemd/user/` | waybar / swayidle / fcitx5 再起動の保全系ユニットのみ |
| `home/.bashrc.d/90-tty-locale.sh` | TTY を英語ロケールに落とす（豆腐対策） |
| `home/.vscode/argv.json` | VS Code の password-store 指定（sway では必須） |
| `packages.txt` | `rpm-ostree` レイヤリング対象 |
| `fonts.txt` | Nerd Fonts の取得対象（フォント本体は含めない） |
| `bootstrap/` | OS インストール自動化（Kickstart） |
| `CLAUDE.md` | **設計ノート**。なぜそうなっているかは全部ここ |

## 設計のポイント

- **コア / 拡張の 2 層**: `config` + `config.d` だけで素の Sway として動く。自作スクリプトに
  依存する設定は `config.ext.d` に分離してあり、`--minimal` で除外できる。
- **ロケールは GUI = 日本語 / TTY = 英語**: VT はコンソールフォント（PSF）の制約で日本語を
  描けないため、復旧作業で使う TTY は英語に保つ。GUI 側だけ日本語にする配線が入っている。
- **常駐は systemd に寄せている**: waybar・swayidle・fcitx5 再起動はすべて `systemd --user`。
  Sway config に残っている `exec` は環境変数の伝播とワークスペース正規化の 2 つだけ
  （どちらも原理的に Sway 側で実行する必要がある）。
- **config には短文だけ**: `exec <command>` / `bindsym <key> exec <command>` のみを書き、
  シェルロジックは `scripts/` の小さなツールに置く。
- **日本語を打つピッカーは rofi**: fuzzel は IME 非対応で日本語変換入力ができないため使わない。
- **設定を編集すればそのままリポジトリの変更になる**: `~/.config/sway` などは
  `~/.dotfiles/home/...` への symlink。手動コピーは不要。
- **キーバインド一覧**: `config` / `config.d` / `config.ext.d` の `#: 機能名` コメントから
  `keybind-rofi.py` が生成する。

詳細な理由・落とし穴・過去にハマった点は [`CLAUDE.md`](CLAUDE.md) にまとめてある。

## 別途手動で行うもの

環境固有・機密のためリポジトリに含めていない。

- **壁紙**: `~/Pictures/background/` に配置する（`sway/config` と `config.d/10-outputs.conf` を参照）。
  壁紙ピッカーで選べる。
- **モニタ設定**: `config.d/10-outputs.conf` と `apply-displays.py` は KTC H27T27 ×2 + 内蔵の
  3 画面前提。自分の環境に合わせて編集する。
- **キーリング**: 解錠プロンプトを消すには `org.gnome.seahorse.Application` で
  「Default keyring」のパスワードを空にする（理由は `CLAUDE.md`）。
- **SSH 鍵**: `~/.ssh/config` と鍵は含まない。`AddKeysToAgent yes` と `ssh-agent.socket` の
  組み合わせで運用する（`CLAUDE.md` 参照）。
- **Gmail / カレンダーの PWA 常駐**: Brave で対象ページを開き「アプリとしてインストール」した後、
  `systemd --user` の oneshot サービスを作る。雛形:

  ```ini
  [Unit]
  Description=Gmail PWA (Brave, scratchpad常駐)
  PartOf=sway-session.target
  After=sway-session.target

  [Service]
  Type=oneshot
  ExecStart=/usr/bin/flatpak run com.brave.Browser --app=https://mail.google.com/
  RemainAfterExit=yes

  [Install]
  WantedBy=sway-session.target
  ```

  ウィンドウの配置ルール（スクラッチパッドへ隠す）は `config.d/20-pwa-notify.conf` に既に入っている。

## 動作確認

```sh
locale-audit                        # ロケール配線の監査（--deep で Flatpak 内も確認）
sway -C -c ~/.config/sway/config    # 構文チェック
swaymsg reload && pgrep swaynag     # reload 後に警告が出ないこと（何も出なければ OK）
```

## 対象環境

Fedora Sway Atomic (Sericea) 専用。`rpm-ostree` を前提にしている。
