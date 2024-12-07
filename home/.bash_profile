# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# load pyenv
export PYENV_ROOT="$HOME/dotfiles/home/pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# load sdkman
source "$HOME/dotfiles/home/sdkman-cli/src/main/bash/sdkman-init.sh"
