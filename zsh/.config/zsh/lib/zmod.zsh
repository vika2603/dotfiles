# zmod: 模块注册与依赖解析。
#
# 每个 modules/*.zsh 声明自己的依赖，再定义 zmod:<name> 作为模块体。
# 加载顺序由依赖图算出，与文件名无关。
#
#   zmod completion --after plugins --phase defer
#   zmod:completion() { compinit }
#
# 参数：
#   --after  A,B    本模块排在 A、B 之后
#   --before C,D    本模块排在 C、D 之前
#   --phase  sync   在提示符渲染前同步执行（默认）
#   --phase  defer  交给 zsh-defer，在 zle 空闲时执行
#
# loader 强制两条不变量，违反即报错而不是静默降级：
#   1. sync 模块不得依赖 defer 模块（defer 依赖 sync 可以）
#   2. compinit 之后 fpath 不得再被修改——这是 forgit 补全失效的 bug 类
#
# zsh-defer 缺失时 defer 模块按同一顺序同步执行，行为退化但顺序不变。

typeset -gA _zmod_after _zmod_before _zmod_phase _zmod_status _zmod_ms
typeset -ga _zmod_names _zmod_order
typeset -g  _zmod_ran=0 _zmod_degraded=0 _zmod_fpath_snapshot=

zmod() {
  local name=$1; shift
  local phase=sync
  local -a after before

  [[ -n $name ]] || { print -ru2 "zmod: 缺少模块名"; return 1 }
  (( ${+_zmod_phase[$name]} )) && { print -ru2 "zmod: 模块 '$name' 重复声明"; return 1 }

  while (( $# )); do
    case $1 in
      --after)  after+=(${(s:,:)2});  shift 2 ;;
      --before) before+=(${(s:,:)2}); shift 2 ;;
      --phase)  phase=$2;             shift 2 ;;
      *) print -ru2 "zmod: $name: 未知参数 '$1'"; return 1 ;;
    esac
  done

  [[ $phase == sync || $phase == defer ]] || {
    print -ru2 "zmod: $name: --phase 只能是 sync 或 defer，收到 '$phase'"; return 1
  }

  _zmod_names+=($name)
  _zmod_after[$name]=${(j:,:)after}
  _zmod_before[$name]=${(j:,:)before}
  _zmod_phase[$name]=$phase
}

# 解析依赖图，结果写入 _zmod_order。失败返回非零并打印原因。
zmod::resolve() {
  local -A indeg
  local -A edges          # edges[from] = "to1 to2 ..."
  local n dep idx
  local -a ready

  for n in $_zmod_names; do indeg[$n]=0; edges[$n]=""; done

  # --after X  => X 先于本模块
  # --before Y => 本模块先于 Y
  for n in $_zmod_names; do
    for dep in ${(s:,:)_zmod_after[$n]}; do
      [[ -n $dep ]] || continue
      (( ${+_zmod_phase[$dep]} )) || {
        print -ru2 "zmod: '$n' 依赖不存在的模块 '$dep'（--after）"; return 1
      }
      [[ ${_zmod_phase[$n]} == sync && ${_zmod_phase[$dep]} == defer ]] && {
        print -ru2 "zmod: sync 模块 '$n' 不能依赖 defer 模块 '$dep'"; return 1
      }
      edges[$dep]+="$n "
      (( indeg[$n]++ ))
    done
    for dep in ${(s:,:)_zmod_before[$n]}; do
      [[ -n $dep ]] || continue
      (( ${+_zmod_phase[$dep]} )) || {
        print -ru2 "zmod: '$n' 引用了不存在的模块 '$dep'（--before）"; return 1
      }
      [[ ${_zmod_phase[$dep]} == sync && ${_zmod_phase[$n]} == defer ]] && {
        print -ru2 "zmod: defer 模块 '$n' 声明 --before sync 模块 '$dep'，无法满足"; return 1
      }
      edges[$n]+="$dep "
      (( indeg[$dep]++ ))
    done
  done

  # Kahn。ready 始终按声明顺序取，保证相同输入得到相同输出。
  _zmod_order=()
  for n in $_zmod_names; do (( indeg[$n] == 0 )) && ready+=($n); done

  while (( $#ready )); do
    n=$ready[1]; shift ready
    _zmod_order+=($n)
    for dep in ${=edges[$n]}; do
      (( indeg[$dep]-- ))
      if (( indeg[$dep] == 0 )); then
        # 插入到 ready 中保持声明顺序
        local -a merged; merged=($ready $dep)
        ready=(${(@)_zmod_names:*merged})
      fi
    done
  done

  if (( $#_zmod_order != $#_zmod_names )); then
    local -a stuck; stuck=(${_zmod_names:|_zmod_order})
    print -ru2 "zmod: 检测到循环依赖，涉及: ${(j:, :)stuck}"
    return 1
  fi
}

# export VAR=${VAR:-默认值} 有个陷阱：当前 shell 一旦 export 过旧默认值，
# exec zsh 会继承它，新默认值永远取不到，必须开全新终端。用这个函数设置
# 可覆盖的默认值，zdoctor 会在实际值与配置期望值不一致时报出来。
typeset -gA _zmod_env_want
zmod::env_default() {
  local var=$1 val=$2
  _zmod_env_want[$var]=$val
  export $var=${(P)var:-$val}
}

zmod::_run_one() {
  local n=$1 t0
  if ! (( ${+functions[zmod:$n]} )); then
    _zmod_status[$n]=missing
    print -ru2 "zmod: 模块 '$n' 已声明但未定义 zmod:$n"
    return 1
  fi
  [[ -n $ZSH_TRACE ]] && t0=$EPOCHREALTIME
  if zmod:$n; then _zmod_status[$n]=ok; else _zmod_status[$n]=failed; fi
  if [[ -n $ZSH_TRACE ]]; then
    _zmod_ms[$n]=$(( (EPOCHREALTIME - t0) * 1000 ))
    printf '%-6s %7.1fms  %s\n' ${_zmod_phase[$n]} ${_zmod_ms[$n]} $n
  fi
}

# compinit 之后 fpath 不得再变。模块体里调用一次快照，末尾校验。
zmod::seal_fpath() { _zmod_fpath_snapshot="${(j:|:)fpath}" }
zmod::check_fpath() {
  [[ -n $_zmod_fpath_snapshot ]] || return 0
  [[ "${(j:|:)fpath}" == "$_zmod_fpath_snapshot" ]] && return 0
  local -a sealed added
  sealed=(${(s:|:)_zmod_fpath_snapshot})
  added=(${fpath:|sealed})
  print -ru2 "zmod: fpath 在 compinit 之后被修改，以下目录的补全未注册："
  print -ru2 "      ${(j:\n      :)added}"
  print -ru2 "      修法：把修改 fpath 的模块加上 --before <compinit 所在模块>"
}

zmod::load() {
  (( _zmod_ran )) && { print -ru2 "zmod: 已加载过，忽略重复调用"; return 0 }
  _zmod_ran=1

  local m
  for m in $ZDOTDIR/modules/*.zsh(N); do source $m; done

  # 解析失败不让 shell 变砖——否则你只能在坏 shell 里修配置。
  # 退回声明顺序继续加载，fpath 守卫仍然生效，zdoctor 会显示降级状态。
  if ! zmod::resolve; then
    _zmod_degraded=1
    _zmod_order=($_zmod_names)
    print -ru2 "zmod: 已退回声明顺序加载，顺序可能不正确——跑 zdoctor 查看"
  fi

  [[ -n $ZSH_TRACE ]] && zmodload zsh/datetime

  local -a deferred
  for m in $_zmod_order; do
    if [[ ${_zmod_phase[$m]} == sync ]]; then
      zmod::_run_one $m
    else
      deferred+=($m)
    fi
  done

  for m in $deferred; do
    if (( ${+functions[zsh-defer]} )); then
      zsh-defer -m -p -c "zmod::_run_one $m"
    else
      zmod::_run_one $m
    fi
  done

  # 所有 defer 跑完后校验不变量
  if (( ${+functions[zsh-defer]} )); then
    zsh-defer -m -p -c 'zmod::check_fpath'
  else
    zmod::check_fpath
  fi
}
