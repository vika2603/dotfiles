# 提示符渲染前必须就位的外部工具。
zmod tools --after core

zmod:tools() {
  eval "$(mise activate zsh)" 2>/dev/null
  eval "$(starship init zsh)" 2>/dev/null

  # forgit: diff/show pager 自动继承 git core.pager (delta)
  export FORGIT_DIR_VIEW='eza -1 --color=always --icons --group-directories-first'
  export FORGIT_CHECKOUT_BRANCH_BRANCH_GIT_OPTS='--sort=-committerdate'
  export FORGIT_LOG_FORMAT='%C(auto)%h%d %s %C(#73daca)%cr %C(#737aa2)%an%Creset'
}
