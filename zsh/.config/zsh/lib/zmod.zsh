# zmod: module registration and dependency resolution.
#
# Each modules/*.zsh declares its dependencies, then defines zmod:<name> as the
# module body. Load order is derived from the dependency graph, not filenames.
#
#   zmod completion --after plugins --phase defer
#   zmod:completion() { compinit }
#
# Arguments:
#   --after  A,B    run after A and B
#   --before C,D    run before C and D
#   --phase  sync   run before the prompt renders (default)
#   --phase  defer  hand to zsh-defer, runs when zle is idle
#
# Two invariants are enforced by the loader, loudly rather than silently:
#   1. A sync module may not depend on a defer module (the reverse is fine).
#   2. fpath is frozen once the completion module finishes. Anything added
#      later is never scanned by compinit — the bug class that silently broke
#      forgit completions.
#
# If zsh-defer is missing, defer modules run inline in the same order.

typeset -gA _zmod_after _zmod_before _zmod_phase _zmod_status _zmod_ms
typeset -ga _zmod_names _zmod_order
# No initialiser: re-sourcing this file must not reset the guard, or
# `source ~/.zshrc` would re-run every module.
typeset -g _zmod_ran _zmod_degraded _zmod_fpath_snapshot
: ${_zmod_ran:=0} ${_zmod_degraded:=0}

zmod() {
  local name=$1; shift
  local phase=sync
  local -a after before

  [[ -n $name ]] || { print -ru2 "zmod: missing module name"; return 1 }
  (( ${+_zmod_phase[$name]} )) && { print -ru2 "zmod: duplicate module '$name'"; return 1 }

  while (( $# )); do
    # Validate before shifting: `shift 2` with one argument left fails without
    # consuming anything, which turns this loop into an infinite one at startup.
    case $1 in
      --after|--before|--phase)
        (( $# >= 2 )) || { print -ru2 "zmod: $name: $1 requires a value"; return 1 } ;;
      *) print -ru2 "zmod: $name: unknown argument '$1'"; return 1 ;;
    esac
    case $1 in
      --after)  after+=(${(s:,:)2})  ;;
      --before) before+=(${(s:,:)2}) ;;
      --phase)  phase=$2             ;;
    esac
    shift 2
  done

  [[ $phase == sync || $phase == defer ]] || {
    print -ru2 "zmod: $name: --phase must be sync or defer, got '$phase'"; return 1
  }

  _zmod_names+=($name)
  _zmod_after[$name]=${(j:,:)after}
  _zmod_before[$name]=${(j:,:)before}
  _zmod_phase[$name]=$phase
}

# Resolve the dependency graph into _zmod_order. Non-zero on failure.
zmod::resolve() {
  local -A indeg edges
  local n dep
  local -a ready

  for n in $_zmod_names; do indeg[$n]=0; edges[$n]=""; done

  # --after X  => X runs before this module
  # --before Y => this module runs before Y
  for n in $_zmod_names; do
    for dep in ${(s:,:)_zmod_after[$n]}; do
      [[ -n $dep ]] || continue
      (( ${+_zmod_phase[$dep]} )) || {
        print -ru2 "zmod: '$n' depends on unknown module '$dep' (--after)"; return 1
      }
      [[ ${_zmod_phase[$n]} == sync && ${_zmod_phase[$dep]} == defer ]] && {
        print -ru2 "zmod: sync module '$n' cannot depend on defer module '$dep'"; return 1
      }
      edges[$dep]+="$n "
      (( indeg[$n]++ ))
    done
    for dep in ${(s:,:)_zmod_before[$n]}; do
      [[ -n $dep ]] || continue
      (( ${+_zmod_phase[$dep]} )) || {
        print -ru2 "zmod: '$n' references unknown module '$dep' (--before)"; return 1
      }
      [[ ${_zmod_phase[$dep]} == sync && ${_zmod_phase[$n]} == defer ]] && {
        print -ru2 "zmod: defer module '$n' declares --before sync module '$dep', unsatisfiable"; return 1
      }
      edges[$n]+="$dep "
      (( indeg[$dep]++ ))
    done
  done

  # Kahn's algorithm. The ready set is always drained in declaration order so
  # the same input always yields the same output.
  _zmod_order=()
  for n in $_zmod_names; do (( indeg[$n] == 0 )) && ready+=($n); done

  while (( $#ready )); do
    n=$ready[1]; shift ready
    _zmod_order+=($n)
    for dep in ${=edges[$n]}; do
      (( indeg[$dep]-- ))
      if (( indeg[$dep] == 0 )); then
        local -a merged; merged=($ready $dep)
        ready=(${(@)_zmod_names:*merged})
      fi
    done
  done

  if (( $#_zmod_order != $#_zmod_names )); then
    local -a stuck; stuck=(${_zmod_names:|_zmod_order})
    print -ru2 "zmod: dependency cycle involving: ${(j:, :)stuck}"
    return 1
  fi
}

# export VAR=${VAR:-default} has a trap: once a parent shell exports the old
# default, exec zsh inherits it and the new default never applies — you need a
# brand new terminal. Use this instead; zdoctor reports the mismatch.
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
    print -ru2 "zmod: module '$n' is declared but zmod:$n is not defined"
    return 1
  fi
  [[ -n $ZSH_TRACE ]] && t0=$EPOCHREALTIME
  if zmod:$n; then _zmod_status[$n]=ok; else _zmod_status[$n]=failed; fi
  if [[ -n $ZSH_TRACE ]]; then
    _zmod_ms[$n]=$(( (EPOCHREALTIME - t0) * 1000 ))
    printf '%-6s %7.1fms  %s\n' ${_zmod_phase[$n]} ${_zmod_ms[$n]} $n
  fi
}

# Called by the completion module once it is done. Anything that touches fpath
# after this point has completions that compinit will never see.
zmod::seal_fpath() { _zmod_fpath_snapshot="${(j:|:)fpath}" }

zmod::check_fpath() {
  [[ -n $_zmod_fpath_snapshot ]] || return 0
  [[ "${(j:|:)fpath}" == "$_zmod_fpath_snapshot" ]] && return 0
  local -a sealed added
  sealed=(${(s:|:)_zmod_fpath_snapshot})
  added=(${fpath:|sealed})
  print -ru2 "zmod: fpath was modified after compinit; completions in these directories are not registered:"
  print -ru2 "      ${(j:\n      :)added}"
  print -ru2 "      fix: give the module that modifies fpath '--before completion'"
  return 1
}

zmod::load() {
  (( _zmod_ran )) && { print -ru2 "zmod: already loaded, ignoring repeat call"; return 0 }

  # Set the guard only once loading is certain to proceed. Setting it before
  # the checks would make a failed load permanent — a corrected retry in the
  # same shell would be refused as "already loaded".
  [[ -n $ZDOTDIR && -d $ZDOTDIR/modules ]] || {
    print -ru2 "zmod: \$ZDOTDIR/modules not found (ZDOTDIR='${ZDOTDIR}') — nothing loaded"
    return 1
  }

  local m
  for m in $ZDOTDIR/modules/*.zsh(N); do source $m; done
  (( $#_zmod_names )) || { print -ru2 "zmod: no modules found in $ZDOTDIR/modules"; return 1 }
  _zmod_ran=1

  # A resolution failure must not brick the shell — otherwise you are stuck
  # repairing the config from a shell with no aliases and no completion.
  # Fall back to declaration order; the fpath guard still runs and zdoctor
  # reports the degraded state.
  if ! zmod::resolve; then
    _zmod_degraded=1
    _zmod_order=($_zmod_names)
    print -ru2 "zmod: falling back to declaration order; run zdoctor for details"
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

  # zsh-defer enables all its actions by default, and actions 1 and 2 redirect
  # stdout and stderr to /dev/null. Without -1 -2 every diagnostic this loader
  # emits from a deferred module is discarded.
  for m in $deferred; do
    if (( ${+functions[zsh-defer]} )); then
      zsh-defer -1 -2 -m -p -c "zmod::_run_one $m"
    else
      zmod::_run_one $m
    fi
  done

  # Verify invariants once every deferred module has run.
  if (( ${+functions[zsh-defer]} )); then
    zsh-defer -1 -2 -m -p -c 'zmod::check_fpath'
  else
    zmod::check_fpath
  fi
}
