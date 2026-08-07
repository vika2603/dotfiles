# antidote 只负责下载。插件全是 kind:clone，由 plugins 模块手动 source。
# 本模块同步执行，因为 .zsh_plugins.zsh 会改 fpath，且 zsh-defer 必须在
# 任何 defer 模块注册前就位。
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

  # 打包到临时文件再 mv -f：clone 失败时 $out 不被破坏，
  # 下次启动 `$src -nt $out` 仍成立会重试，而不是缓存一个空 bundle。
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

  # zsh-defer 必须在 zmod::load 注册 defer 模块之前可用。
  local defer=$ANTIDOTE_HOME/github.com/romkatv/zsh-defer/zsh-defer.plugin.zsh
  [[ -f $defer ]] && source $defer
  return 0
}
