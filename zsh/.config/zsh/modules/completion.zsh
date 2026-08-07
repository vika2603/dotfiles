# compinit runs here and is the fpath deadline: completions added afterwards
# are never registered. Modules adding completion directories declare
# --before completion.
zmod completion --after plugins --phase defer

zmod:completion() {
  zmodload zsh/complist
  autoload -Uz compinit
  compinit
  _comp_options+=(globdots)

  # fzf-tab must load after compinit. It appends its own lib to fpath — those
  # are ftb-* autoloaded functions, not completions, so seal after it.
  source $ANTIDOTE_HOME/github.com/Aloxaf/fzf-tab/fzf-tab.plugin.zsh
  _fsh_theme

  # From here on any fpath change is reported by zmod::check_fpath.
  zmod::seal_fpath
  return 0
}
