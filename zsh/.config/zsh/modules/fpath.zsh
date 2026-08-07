# The single owner of fpath. Add completion directories here, or declare
# --before completion in your own module.
zmod fpath --after core

zmod:fpath() {
  fpath=($ZDOTDIR/functions $ZDOTDIR/completions $fpath)
  [[ -d /opt/homebrew/share/zsh/site-functions ]] && \
    fpath=(/opt/homebrew/share/zsh/site-functions $fpath)

  # autoload only registers; resolution happens at call time, so fpath
  # must be settled first.
  autoload -Uz $ZDOTDIR/functions/*(N-.:t)
}
