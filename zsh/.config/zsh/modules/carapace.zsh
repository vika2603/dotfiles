# carapace claims ~2000 commands with a single compdef, so it must run after compinit.
#zmod after=completion phase=defer

(( $+commands[carapace] )) || return 0

zmod::env_default CARAPACE_BRIDGES zsh
# git: zsh's native _git is faster and more complete; carapace costs ~30ms per Tab
zmod::env_default CARAPACE_EXCLUDES kill,killall,pkill,git
zmod::env_default CARAPACE_MATCH 1   # case-insensitive matching

# Only BRIDGES and EXCLUDES change the generated script; MATCH is read at
# runtime, so it is deliberately absent from the signature.
local cache=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/carapace.zsh
local sig=$cache.sig
local want="${CARAPACE_BRIDGES}|${CARAPACE_EXCLUDES}"
[[ -d ${cache:h} ]] || mkdir -p ${cache:h}
if [[ ! -r $cache || $commands[carapace] -nt $cache || ! -r $sig || "$(< $sig)" != "$want" ]]; then
  local tmp=$cache.tmp.$$
  if carapace _carapace >| $tmp && [[ -s $tmp ]]; then
    mv -f $tmp $cache
    print -r -- "$want" >| $sig
  else
    rm -f $tmp
  fi
fi
[[ -r $cache ]] && source $cache
