# bootstrap — OS インストールの自動化

`fedora-sway-atomic.ks` は Fedora Sway Atomic (Sericea) を自動インストールする Kickstart。

## 2 層に分かれている理由

| 層 | 担当 | 実行タイミング |
|---|---|---|
| `fedora-sway-atomic.ks` | パーティション・LUKS・ロケール・ユーザー作成 | OS インストール時 |
| `../install.sh` | 設定の symlink・パッケージレイヤリング・フォント・systemd ユニット | 初回ログイン後 |

Atomic の Kickstart `%post` はイメージが deploy された直後の状態しか触れず、
**`rpm-ostree` によるパッケージレイヤリングができない**。`systemd --user` も動いていないため
ユニットの有効化もできない。よって `%post` ではヒントを置くだけに留めている。

## 完全自動にはならない点

意図的に 2 箇所で対話入力が入る。**公開リポジトリに機密を書かないため**。

- **LUKS パスフレーズ**: `--passphrase` を指定していないので Anaconda が尋ねる
- **ユーザーのパスワード**: `firstboot --reconfig` で初回起動時に設定する

Kickstart で完結させたい場合は `.ks` 内のコメントに従って `user --iscrypted` を有効にする
（生成したハッシュを公開リポジトリにコミットしないこと）。

## VM で検証する

実機の前に必ず VM で通すこと。

```sh
# 1) Kickstart を HTTP で配る（VM から見える IP を使う。libvirt の既定は 192.168.122.1）
python3 -m http.server 8000 --directory ~/.dotfiles/bootstrap &

# 2) VM を作る
virt-install \
  --name fedora-sway-ks-test \
  --memory 4096 --vcpus 2 \
  --disk size=40,format=qcow2 \
  --cdrom ~/Downloads/Fedora-Sericea-ostree-x86_64-44-1.x.iso \
  --os-variant fedora-rawhide \
  --graphics spice
```

Atomic の ISO は Live 形式なので `--location` ではなく `--cdrom` を使う。
起動メニューで `e`（または `Tab`）を押し、`linux` 行の末尾に次を追記する。

```
inst.ks=http://192.168.122.1:8000/fedora-sway-atomic.ks
```

`--location` が使える netinst 系 ISO なら `--extra-args "inst.ks=..."` で渡せる。

### 確認すること

1. `ostreesetup` の `--ref` が ISO の内容と一致しているか
   （インストーラの `Ctrl+Alt+F2` で `ostree --repo=/ostree/repo refs`）
2. LUKS パスフレーズのプロンプトが出て、暗号化されたディスクにインストールされるか
3. 初回ログイン時に `/etc/profile.d/zz-dotfiles-hint.sh` の案内が出るか
4. 案内通り `install.sh` を実行して、symlink・フォント・ユニットが揃うか

## 構文チェック

```sh
ksvalidator bootstrap/fedora-sway-atomic.ks   # pykickstart パッケージ
```

## 将来: bootc / OSTree native container

`Containerfile` でパッケージレイヤリングを OS イメージに焼き込めば、`install.sh` の
レイヤリング工程（再起動を伴う）が不要になり、再構築が高速かつ再現的になる。
`packages.txt` を `RUN dnf install` に変換する形にすれば定義を共有できる。
詳細は `../CLAUDE.md` の「将来の方針」を参照。

**Ignition は使えない** — Fedora CoreOS 専用で Silverblue/Sericea 系では利用できない。
