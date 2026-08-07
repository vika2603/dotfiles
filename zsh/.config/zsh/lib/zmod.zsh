# zmod: module scheduling for modules/*.zsh
#
# A module file IS the module. Its filename is its identity; a header comment
# describes only when it runs:
#
#   # modules/completion.zsh
#   #zmod after=plugins phase=defer
#
#   compinit
#   ...
#
# The loader reads just the header of every file, resolves the dependency
# graph, then sources the files in the resolved order. Header keys:
#
#   after=A,B    run after A and B
#   before=C,D   run before C and D
#   phase=sync   run before the prompt renders (default)
#   phase=defer  hand to zsh-defer, runs when zle is idle
#
# Two invariants are enforced, loudly rather than silently:
#   1. A sync module may not depend on a defer module (the reverse is fine).
#   2. fpath is frozen once the completion module finishes. Anything added
#      later is never scanned by compinit — the bug class that silently broke
#      forgit completions.
#
# `source` reports only a file's last command, so it cannot prove a module
# succeeded throughout. Write fatal steps as `cmd || return 1` and let optional
# ones fail explicitly; enabling ERR_RETURN globally would change the semantics
# of every module.
#
# If zsh-defer is missing, defer modules run inline in the same order.
#
# Shell options set by a defer-phase module do not persist: zsh-defer runs its
# queue under `emulate -L zsh`, which restores options on return. The inline
# fallback deliberately does the same so a module behaves identically whether
# or not zsh-defer is installed. Anything that must change options durably
# belongs in a sync module.
#
# Alias expansion is owned by the loader while a file is sourced, so a module
# cannot durably unsetopt aliases either.

typeset -gA _zmod_after _zmod_before _zmod_phase _zmod_status _zmod_ms _zmod_file
typeset -ga _zmod_names _zmod_order _zmod_fpath_sealed _zmod_bad_decls
# No initialiser: re-sourcing this file must not reset the guard, or
# `source ~/.zshrc` would re-run every module.
typeset -g _zmod_ran _zmod_degraded _zmod_fpath_is_sealed
# never | preflight-failed | no-files | sourced
typeset -g _zmod_load_state
: ${_zmod_ran:=0} ${_zmod_degraded:=0} ${_zmod_fpath_is_sealed:=0}
: ${_zmod_load_state:=never}

zmod::_hdr_err() {
  _zmod_bad_decls+=("$1")
  print -ru2 "zmod: $1"
}

# Read the leading comment block of a file and register what it declares.
# Nothing in the file is executed here.
zmod::_read_header() {
  # no_err_return: the loader's own control flow uses `[[ ]] && { }` throughout,
  # which returns non-zero whenever the condition is false. A caller's
  # ERR_RETURN would abort parsing at the first such statement.
  setopt localoptions extended_glob no_err_return
  local _zmod_path=$1
  local _zmod_name=${${_zmod_path:t}:r}
  local _zmod_line _zmod_spec _zmod_kv _zmod_key _zmod_val _zmod_part
  local _zmod_phase_val=sync
  local -a _zmod_after_val _zmod_before_val

  [[ $_zmod_name == [A-Za-z_][A-Za-z0-9_-]# ]] || {
    zmod::_hdr_err "${_zmod_path:t}: filename is not a usable module name (letters, digits, - and _)"
    return 1
  }
  (( ${+_zmod_phase[$_zmod_name]} )) && {
    zmod::_hdr_err "${_zmod_path:t}: duplicate module name '$_zmod_name'"
    return 1
  }

  # $(<file) is a builtin read with no fork, and splitting on newlines handles
  # a missing final newline without needing to append a terminator. `read` in a
  # loop would skip an unterminated last line, and a process substitution to
  # work around that costs a subprocess per module at every startup.
  local -i _zmod_seen=0
  local -a _zmod_lines
  _zmod_lines=("${(@f)$(<$_zmod_path)}")
  for _zmod_line in "${_zmod_lines[@]}"; do
    if [[ $_zmod_line == '#zmod'(| *) ]]; then
      (( _zmod_seen )) && {
        zmod::_hdr_err "${_zmod_path:t}: more than one '#zmod' line"; return 1
      }
      _zmod_seen=1
      _zmod_spec=${_zmod_line#\#zmod}
      continue                  # keep reading: a second header must be caught
    fi
    [[ $_zmod_line == \#* || -z ${_zmod_line// } ]] && continue
    break                       # first real line: the header block is over
  done

  (( _zmod_seen )) || {
    zmod::_hdr_err "${_zmod_path:t}: no '#zmod' header line"
    return 1
  }

  local -A _zmod_seen_key
  for _zmod_kv in ${=_zmod_spec}; do
    [[ $_zmod_kv == *=* ]] || {
      zmod::_hdr_err "$_zmod_name: '$_zmod_kv' is not key=value"; return 1
    }
    _zmod_key=${_zmod_kv%%=*} _zmod_val=${_zmod_kv#*=}
    [[ -n $_zmod_val ]] || { zmod::_hdr_err "$_zmod_name: '$_zmod_key' has an empty value"; return 1 }
    # Last-one-wins would silently discard whichever the author meant.
    (( ${+_zmod_seen_key[$_zmod_key]} )) && {
      zmod::_hdr_err "$_zmod_name: '$_zmod_key' given more than once"; return 1
    }
    _zmod_seen_key[$_zmod_key]=1

    case $_zmod_key in
      after|before)
        # An unquoted array in a for loop drops empty elements, which would
        # skip exactly the entries being checked for.
        local -a _zmod_parts=("${(@s:,:)_zmod_val}")
        for _zmod_part in "${_zmod_parts[@]}"; do
          [[ -n $_zmod_part ]] || {
            zmod::_hdr_err "$_zmod_name: $_zmod_key='$_zmod_val' has an empty entry"; return 1
          }
        done
        [[ $_zmod_key == after ]] && _zmod_after_val+=($_zmod_parts) \
                                  || _zmod_before_val+=($_zmod_parts) ;;
      phase)
        [[ $_zmod_val == sync || $_zmod_val == defer ]] || {
          zmod::_hdr_err "$_zmod_name: phase must be sync or defer, got '$_zmod_val'"; return 1
        }
        _zmod_phase_val=$_zmod_val ;;
      *) zmod::_hdr_err "$_zmod_name: unknown header key '$_zmod_key'"; return 1 ;;
    esac
  done

  _zmod_names+=($_zmod_name)
  _zmod_file[$_zmod_name]=$_zmod_path
  _zmod_after[$_zmod_name]=${(j:,:)_zmod_after_val}
  _zmod_before[$_zmod_name]=${(j:,:)_zmod_before_val}
  _zmod_phase[$_zmod_name]=$_zmod_phase_val
}

# Resolve the dependency graph into _zmod_order. Non-zero on failure.
zmod::resolve() {
  setopt localoptions no_err_return
  local -A indeg edges
  local n dep
  local -a ready

  for n in $_zmod_names; do indeg[$n]=0; edges[$n]=""; done

  # after=X  => X runs before this module
  # before=Y => this module runs before Y
  for n in $_zmod_names; do
    for dep in ${(s:,:)_zmod_after[$n]}; do
      [[ -n $dep ]] || continue
      (( ${+_zmod_phase[$dep]} )) || {
        print -ru2 "zmod: '$n' depends on unknown module '$dep' (after=)"; return 1
      }
      [[ ${_zmod_phase[$n]} == sync && ${_zmod_phase[$dep]} == defer ]] && {
        print -ru2 "zmod: sync module '$n' cannot depend on defer module '$dep'"; return 1
      }
      edges[$dep]+="$n "
      (( indeg[$n] += 1 ))
    done
    for dep in ${(s:,:)_zmod_before[$n]}; do
      [[ -n $dep ]] || continue
      (( ${+_zmod_phase[$dep]} )) || {
        print -ru2 "zmod: '$n' references unknown module '$dep' (before=)"; return 1
      }
      [[ ${_zmod_phase[$dep]} == sync && ${_zmod_phase[$n]} == defer ]] && {
        print -ru2 "zmod: defer module '$n' declares before=$dep, a sync module: unsatisfiable"; return 1
      }
      edges[$n]+="$dep "
      (( indeg[$dep] += 1 ))
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
      (( indeg[$dep] -= 1 ))
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
# brand new terminal. Warn at the moment it happens rather than waiting for
# someone to think of running a diagnostic.
zmod::env_default() {
  local var=$1 val=$2
  export $var=${(P)var:-$val}
  [[ ${(P)var} == $val ]] || print -ru2 \
    "zmod: $var is '${(P)var}' inherited from a parent shell, config wants '$val' — exec zsh cannot change it, open a new terminal"
  return 0
}

# A conditional alias fails silently: when the command is absent the alias is
# simply never defined, which is indistinguishable from a config that never
# wanted it. Record the intent; zmod::verify checks it once everything has run.
#
# The check cannot happen here. The failure being guarded against is running
# too early — a module scheduled before the one that puts the command on PATH
# sees $+commands as false and takes the "not installed" branch legitimately.
# Only a pass after every module has run can tell the two cases apart.
typeset -gA _zmod_alias_want
zmod::alias_if() {
  local cmd=$1 name=$2 body=$3
  _zmod_alias_want[$name]=$cmd
  (( $+commands[$cmd] )) && alias $name="$body"
  return 0
}

# Final pass, queued after every module. Reports what only becomes knowable
# once the whole configuration is in place.
zmod::verify() {
  local name cmd
  # A claimed invariant that is only checked when someone remembered to arm it
  # is not enforced. If the completion module finished without sealing, every
  # later fpath change goes unreported.
  [[ ${_zmod_status[completion]} == ok ]] && (( ! _zmod_fpath_is_sealed )) && print -ru2 \
    "zmod: completion module finished without calling zmod::seal_fpath; fpath is unguarded"
  zmod::check_fpath
  for name in ${(ok)_zmod_alias_want}; do
    cmd=${_zmod_alias_want[$name]}
    (( $+commands[$cmd] )) || continue
    [[ -n ${aliases[$name]} ]] || print -ru2 \
      "zmod: $cmd is on PATH but alias '$name' was never defined — the module defining it likely runs before the one providing $cmd"
  done
  return 0
}

# Deliberately no `emulate -L zsh` and no LOCAL_OPTIONS: those would undo any
# setopt a module performs. Locals are _zmod_-prefixed so a module sourced into
# this scope cannot collide with them.
zmod::_run_file() {
  local _zmod_n=$1 _zmod_t0 _zmod_timing=0
  local _zmod_f=${_zmod_file[$_zmod_n]}

  if [[ ! -r $_zmod_f ]]; then
    _zmod_status[$_zmod_n]=missing
    print -ru2 "zmod: module file for '$_zmod_n' is unreadable: $_zmod_f"
    return 1
  fi

  # Without zsh/datetime EPOCHREALTIME is unset and arithmetic silently yields
  # 0, so every module would report 0.0ms. Say so instead.
  [[ -n $ZSH_TRACE ]] && (( ${+EPOCHREALTIME} )) && { _zmod_timing=1; _zmod_t0=$EPOCHREALTIME }

  # Aliases are expanded when a file is parsed, and modules are parsed as they
  # run — so anything after the aliases module would inherit the user's
  # interactive aliases (rm -i, grep --colour, mv -v). The previous
  # function-wrapper design was immune only by accident: bodies were parsed
  # before any alias existed. Module code should behave like a script.
  # Toggled by hand rather than via LOCAL_OPTIONS, which would also undo any
  # setopt the module performs.
  local -i _zmod_aliases_on=0
  [[ -o aliases ]] && _zmod_aliases_on=1
  unsetopt aliases

  # `always` so the option is restored and the status recorded even if the
  # caller has ERR_RETURN set, which would otherwise abort this function at the
  # source line and skip both.
  local -i _zmod_rc=0
  {
    source $_zmod_f
  } always {
    # Read the status here rather than after the source: under ERR_RETURN a
    # failing source leaves the try list immediately, so an assignment placed
    # after it never runs and the module is recorded as successful.
    _zmod_rc=$?
    (( _zmod_aliases_on )) && setopt aliases
    if (( _zmod_rc == 0 )); then
      _zmod_status[$_zmod_n]=ok
    else
      _zmod_status[$_zmod_n]=failed
      print -ru2 "zmod: module '$_zmod_n' returned $_zmod_rc (${_zmod_f:t})"
    fi

    # Inside the always block too: under a caller's ERR_RETURN the function
    # returns as soon as this block ends, so a trace line placed after it would
    # be printed for successful modules and silently skipped for failed ones.
    if (( _zmod_timing )); then
      _zmod_ms[$_zmod_n]=$(( (EPOCHREALTIME - _zmod_t0) * 1000 ))
      printf '%-6s %7.1fms  %s\n' ${_zmod_phase[$_zmod_n]} ${_zmod_ms[$_zmod_n]} $_zmod_n
    elif [[ -n $ZSH_TRACE ]]; then
      printf '%-6s %9s  %s\n' ${_zmod_phase[$_zmod_n]} 'no clock' $_zmod_n
    fi
  }
}

# zsh-defer resumes its queue under `emulate -L zsh`, which both resets options
# to zsh defaults for the module and rolls them back afterwards. The inline
# fallback matches that exactly; matching only the rollback would still let a
# module see EXTENDED_GLOB on here and off there.
zmod::_run_inline() {
  emulate -L zsh
  zmod::_run_file $1
}

# Called by the completion module once it is done. Anything that touches fpath
# after this point has completions compinit will never see. Kept as an array;
# serialising to a delimited string breaks on a path containing the delimiter.
zmod::seal_fpath() { _zmod_fpath_sealed=($fpath); _zmod_fpath_is_sealed=1 }

zmod::check_fpath() {
  (( _zmod_fpath_is_sealed )) || return 0

  # Exact positional comparison: fpath order decides which definition wins when
  # two directories provide the same function, so a reorder is a real change
  # even though the set is identical.
  local -i i same=1
  if (( $#fpath == $#_zmod_fpath_sealed )); then
    for (( i = 1; i <= $#fpath; i++ )); do
      [[ $fpath[i] == $_zmod_fpath_sealed[i] ]] || { same=0; break }
    done
  else
    same=0
  fi
  (( same )) && return 0

  local -a added removed
  added=(${fpath:|_zmod_fpath_sealed})
  removed=(${_zmod_fpath_sealed:|fpath})
  print -ru2 "zmod: fpath changed after it was sealed; compinit's scan is stale:"
  (( $#added ))   && print -ru2 "      added:   ${(j:\n               :)added}"
  (( $#removed )) && print -ru2 "      removed: ${(j:\n               :)removed}"
  (( $#added || $#removed )) || print -ru2 "      reordered (same entries, different precedence)"
  print -ru2 "      fix: give the module that modifies fpath 'before=completion'"
  return 1
}

zmod::load() {
  # LOCAL_OPTIONS is not usable here: it would roll back every setopt a sync
  # module performs. Toggle ERR_RETURN by hand and restore it in an always
  # block so every exit path is covered. Modules therefore run without it,
  # matching what zsh-defer's `emulate -L zsh` already does for defer modules.
  local -i _zmod_er=0
  [[ -o err_return ]] && _zmod_er=1
  unsetopt err_return
  {
    zmod::_load_body "$@"
  } always {
    (( _zmod_er )) && setopt err_return
  }
}

zmod::_load_body() {
  (( _zmod_ran )) && { print -ru2 "zmod: already loaded, ignoring repeat call"; return 0 }

  # Guards are set only once loading is certain to proceed; setting them before
  # the checks would make a failed load permanent, with no way to retry in the
  # same shell after correcting it.
  _zmod_load_state=preflight-failed
  [[ -n $ZDOTDIR && -d $ZDOTDIR/modules ]] || {
    print -ru2 "zmod: \$ZDOTDIR/modules not found (ZDOTDIR='${ZDOTDIR}') — nothing loaded"
    return 1
  }

  local m
  local -i read_count=0
  _zmod_bad_decls=()
  for m in $ZDOTDIR/modules/*.zsh(N-.); do
    (( read_count += 1 ))
    zmod::_read_header $m
  done
  (( read_count )) && _zmod_load_state=sourced || _zmod_load_state=no-files

  (( $#_zmod_names )) || {
    print -ru2 "zmod: no usable modules in $ZDOTDIR/modules"
    return 1
  }
  _zmod_ran=1

  # A resolution failure must not brick the shell — otherwise you are repairing
  # the config from a shell with no aliases and no completion. Fall back to
  # declaration order; the fpath guard still runs.
  if ! zmod::resolve; then
    _zmod_degraded=1
    _zmod_order=($_zmod_names)
    print -ru2 "zmod: falling back to declaration order; ordering is not guaranteed"
  fi

  [[ -n $ZSH_TRACE ]] && zmodload zsh/datetime

  local -a deferred
  for m in $_zmod_order; do
    if [[ ${_zmod_phase[$m]} == sync ]]; then
      zmod::_run_file $m || true
    else
      deferred+=($m)
    fi
  done

  # zsh-defer enables all its actions by default, and actions 1 and 2 redirect
  # stdout and stderr to /dev/null. Without -1 -2 every diagnostic a deferred
  # module emits is discarded.
  for m in $deferred; do
    if (( ${+functions[zsh-defer]} )); then
      zsh-defer -1 -2 -m -p -c "zmod::_run_file ${(q)m} || true"
    else
      zmod::_run_inline $m || true
    fi
  done

  if (( ${+functions[zsh-defer]} )); then
    zsh-defer -1 -2 -m -p -c 'zmod::verify'
  else
    zmod::verify
  fi
}
