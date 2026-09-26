# greetd（Sericea/Sway 時代のログイン構成、退役）

2026-09-27 に Kinoite 側のログインを KDE 標準の Plasma Login Manager(plasmalogin) に切り替え、
greetd / greetd-selinux / tuigreet のレイヤを外した。切り戻し用に /etc にあった実体を写している。
Sericea デプロイメント（rpm-ostree で pin）は独自の /etc を持つのでこのファイルは不要。
復元するなら: greetd 系を `rpm-ostree install`、`greetd@.service` を /etc/systemd/system/ へ、
`config-tty1.toml` を /etc/greetd/ へ（tty2/3 用の config は同内容の複製で未使用だったため保管しない）、`systemctl enable greetd@tty1`。
