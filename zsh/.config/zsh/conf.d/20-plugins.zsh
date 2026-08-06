# Plugin manager (antidote) + custom fpath + deferred plugin loading.

fpath=($ZDOTDIR/functions $ZDOTDIR/completions $fpath)
autoload -Uz $ZDOTDIR/functions/*(N-.:t)

ANTIDOTE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}/antidote
export ABBR_USER_ABBREVIATIONS_FILE=$ZDOTDIR/abbreviations

() {
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

  # Bundle to a temp then mv -f, so a failed clone leaves $out untouched and the
  # `$src -nt $out` check retries next startup instead of caching an empty bundle.
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
}

_load_deferred_plugins() {
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

  compinit
  _comp_options+=(globdots)
  source $base/Aloxaf/fzf-tab/fzf-tab.plugin.zsh
  _fsh_theme
  fpath=(${FORGIT_INSTALL_DIR}/completions $fpath)
}

local _defer=$ANTIDOTE_HOME/github.com/romkatv/zsh-defer/zsh-defer.plugin.zsh
if [[ -f $_defer ]]; then
  source $_defer
  zsh-defer -m -p _load_deferred_plugins
else
  _load_deferred_plugins
fi

[[ -d /opt/homebrew/share/zsh/site-functions ]] && fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
