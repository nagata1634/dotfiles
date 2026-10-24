# 履歴: 件数を増やし、重複と先頭が空白のコマンドは残さない。
# histappend は Fedora の既定で有効。プロンプトのたびに追記して、タブを強制終了しても失わない
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
PROMPT_COMMAND+=('history -a')   # Fedora では PROMPT_COMMAND が配列
