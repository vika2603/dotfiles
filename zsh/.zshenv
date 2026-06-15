export XDG_CONFIG_HOME=$HOME/.config
export XDG_CACHE_HOME=$HOME/.cache
export XDG_DATA_HOME=$HOME/.local/share

export LANG=${LANG:-"en_US.UTF-8"}
export LC_COLLATE=${LC_COLLATE:-C}

ZDOTDIR=$XDG_CONFIG_HOME/zsh
skip_global_compinit=1

export LESSHISTFILE=/dev/null

[[ -d /opt/homebrew ]] && export PATH=/opt/homebrew/bin:$PATH
[[ -d /usr/local/Homebrew ]] && export PATH=/usr/local/bin:$PATH
export PATH=$HOME/.local/bin:$ZDOTDIR/bin:$PATH

export RUSTUP_HOME=$HOME/.local/rustup
export CARGO_HOME=$HOME/.local/cargo
export GOPATH="$HOME/.local/go"
export GOBIN="$GOPATH/bin"
export GOTOOLCHAIN=local

if { [[ ! -o interactive ]] || [[ -n "${ZSH_EXECUTION_STRING:-}" ]]; } \
    && [[ -z "${__PATHCTL_SCRIPT:-}" ]]; then
    eval "$(pathctl activate)"
fi

[ -f $HOME/.zshenv.local ] && source $HOME/.zshenv.local
