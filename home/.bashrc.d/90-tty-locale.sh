# 素の VT(/dev/tty1-6 のテキストコンソール)の対話シェルだけ英語ロケールに落とす。
# VT はコンソールフォント(PSF)を使い fontconfig を参照しないため日本語が豆腐になる。
# 理由と順序の要点は ~/.dotfiles/CLAUDE.md の「ロケール分離」を参照。
#
# $- の対話ガードは必須。greetd は bash -l -c(非対話)でセッションを起動するため、
# これが無いと GUI セッションまで英語に落ちる。
if [[ $- == *i* ]] && [ "$TERM" = "linux" ]; then
    case "$(tty 2>/dev/null)" in
        /dev/tty[0-9]*)
            export LANG=C.UTF-8
            export LC_ALL=C.UTF-8
            ;;
    esac
fi
