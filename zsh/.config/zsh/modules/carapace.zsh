# carapace 用一条 compdef 接管约 2000 个命令，所以必须在 compinit 之后。
zmod carapace --after completion --phase defer

zmod:carapace() {
  (( $+commands[carapace] )) || return 0

  zmod::env_default CARAPACE_BRIDGES zsh
  # git: zsh 原生 _git 更快更全，carapace 每次 Tab 有 ~30ms spawn 开销
  zmod::env_default CARAPACE_EXCLUDES kill,killall,pkill,git
  zmod::env_default CARAPACE_MATCH 1   # case-insensitive matching

  # 只有 BRIDGES 和 EXCLUDES 会改变生成的脚本，MATCH 是运行时读取，
  # 所以签名里不含 MATCH——加进去会导致无谓的重建。
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
  return 0
}
