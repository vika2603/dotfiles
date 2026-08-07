zmod plugins --after plugin-manager --phase defer

zmod:plugins() {
  local base=$ANTIDOTE_HOME/github.com p f
  for p in \
    hlissner/zsh-autopair \
    olets/zsh-abbr \
    zsh-users/zsh-autosuggestions \
    zdharma-continuum/fast-syntax-highlighting \
    wfxr/forgit
  do
    f=$base/$p/${p#*/}.plugin.zsh
    [[ -f $f ]] && source $f
  done

  eval "$(abbr export-aliases)" &>/dev/null
  return 0
}
