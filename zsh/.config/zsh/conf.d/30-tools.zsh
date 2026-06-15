# External tool initialization + fzf defaults + editor.

# Sync: needed before the prompt renders.
eval "$(mise activate zsh --shims)" 2>/dev/null
eval "$(starship init zsh)" 2>/dev/null

# Defer when zsh-defer is loaded, otherwise inline-eval as a fallback.
_lazy() {
  if (( $+functions[zsh-defer] )); then
    zsh-defer -c "$1"
  else
    eval "$1" 2>/dev/null
  fi
}
_lazy 'eval "$(pathctl activate)"'
_lazy 'eval "$(zoxide init zsh)"'
_lazy '(( $+commands[atuin]  )) && eval "$(atuin init zsh --disable-up-arrow)"'
_lazy '(( $+commands[direnv] )) && eval "$(direnv hook zsh)"'

# forgit: diff/show pager 自动继承 git core.pager (delta)
export FORGIT_DIR_VIEW='eza -1 --color=always --icons --group-directories-first'
export FORGIT_CHECKOUT_BRANCH_BRANCH_GIT_OPTS='--sort=-committerdate'
export FORGIT_LOG_FORMAT='%C(auto)%h%d %s %C(#73daca)%cr %C(#737aa2)%an%Creset'

