# Completion + fzf-tab.

WORDCHARS=''
zmodload zsh/complist
autoload -Uz compinit

if (( $+commands[carapace] )); then
  export CARAPACE_BRIDGES=${CARAPACE_BRIDGES:-zsh}
  export CARAPACE_EXCLUDES=${CARAPACE_EXCLUDES:-kill,killall,pkill}

  _carapace_load='
    local cache=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/carapace.zsh
    local sig=$cache.sig
    local want="${CARAPACE_BRIDGES}|${CARAPACE_EXCLUDES}"
    [[ -d ${cache:h} ]] || mkdir -p ${cache:h}
    if [[ ! -r $cache || $commands[carapace] -nt $cache || ! -r $sig || "$(< $sig)" != "$want" ]]; then
      carapace _carapace >| $cache
      print -r -- "$want" >| $sig
    fi
    source $cache
  '
  if (( $+functions[zsh-defer] )); then
    zsh-defer -c $_carapace_load
  else
    eval $_carapace_load
  fi
  unset _carapace_load
fi

zstyle ':completion:*' menu no
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path ${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compcache
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' sort false
zstyle ':completion:*' group-name ''
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:options' description yes
zstyle ':completion:*:options' auto-description '%d'

zstyle ':completion:*' completer _complete _match _approximate
zstyle ':completion:*:match:*'       original only
zstyle ':completion:*:approximate:*' max-errors 1 numeric

zstyle ':completion:*:*:kill:*:processes'   list-colors '=(#b) #([0-9]#)*=01;34=0=01'
zstyle ':completion:*:*:*:*:processes'      command "ps -u $USERNAME -o pid,user,comm -w -w"
zstyle ':completion:*:cd:*'                 tag-order local-directories directory-stack path-directories

zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
zstyle ':fzf-tab:*' query-string prefix
zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' active-group-style bold underline
zstyle ':fzf-tab:*' fzf-flags --tiebreak=begin,chunk,length
zstyle ':fzf-tab:*' prefix $'▎'
zstyle ':fzf-tab:*' default-color $'\e[38;2;192;202;245m'
zstyle ':fzf-tab:*' group-colors \
  $'\e[38;2;157;121;214m' \
  $'\e[38;2;122;162;247m' \
  $'\e[38;2;115;218;202m' \
  $'\e[38;2;158;206;106m' \
  $'\e[38;2;224;175;104m' \
  $'\e[38;2;255;158;100m' \
  $'\e[38;2;247;118;142m' \
  $'\e[38;2;220;142;217m'
zstyle ':fzf-tab:*' fzf-bindings-default \
 'tab:down' \
 'btab:up' \
 'ctrl-j:toggle+down' \
 'ctrl-k:toggle+up' \
 'ctrl-l:toggle' \
 'bspace:backward-delete-char/eof'

zstyle ':fzf-tab:complete:(cd|pushd|popd|z|zoxide|__zoxide_z):*' fzf-flags --no-multi
zstyle ':fzf-tab:complete:cd:*'                       fzf-preview 'eza -1 --color=always --icons=auto $realpath'
zstyle ':fzf-tab:complete:kill:argument-rest'         fzf-preview 'ps -p $word -o command -w -w | sed -e 1d'
zstyle ':fzf-tab:complete:kill:argument-rest'         fzf-flags '--preview-window=down:3:wrap'
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':fzf-tab:complete:(-parameter-|-brace-parameter-|export|unset|expand):*' \
  fzf-preview 'echo ${(P)word}'
