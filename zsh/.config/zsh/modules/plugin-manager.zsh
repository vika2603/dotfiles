# antidote only downloads. Every plugin is kind:clone and sourced manually by
# the plugins module. This runs sync because .zsh_plugins.zsh modifies fpath and
# zsh-defer must exist before any defer module is registered.
zmod plugin-manager --after fpath

zmod:plugin-manager() {
  ANTIDOTE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}/antidote
  export ABBR_USER_ABBREVIATIONS_FILE=$ZDOTDIR/abbreviations

  local antidote_zsh
  for antidote_zsh in \
    ${HOMEBREW_PREFIX:-/usr/local}/opt/antidote/share/antidote/antidote.zsh \
    $ANTIDOTE_HOME/antidote/antidote.zsh; do
    [[ -f $antidote_zsh ]] && break
  done
  if [[ ! -f $antidote_zsh ]]; then
    print -P "%F{yellow}antidote not found, cloning...%f"
    git clone --depth=1 https://github.com/mattmc3/antidote.git $ANTIDOTE_HOME/antidote || return 1
    antidote_zsh=$ANTIDOTE_HOME/antidote/antidote.zsh
  fi
  source $antidote_zsh

  # Bundle to a temp file then mv -f, so a failed clone leaves $out untouched and
  # the `$src -nt $out` check retries next startup instead of caching an empty bundle.
  local src=$ZDOTDIR/.zsh_plugins.txt out=$ZDOTDIR/.zsh_plugins.zsh
  if [[ ! -f $out || $src -nt $out ]]; then
    local tmp=$out.tmp.$$
    if antidote bundle <$src >$tmp; then
      mv -f $tmp $out
    else
      print -P "%F{red}antidote bundle failed; keeping previous $out:t%f" >&2
      rm -f $tmp
    fi
  fi
  [[ -f $out ]] && source $out

  # zsh-defer must be available before zmod::load registers deferred modules.
  local defer=$ANTIDOTE_HOME/github.com/romkatv/zsh-defer/zsh-defer.plugin.zsh
  [[ -f $defer ]] && source $defer
  return 0
}
