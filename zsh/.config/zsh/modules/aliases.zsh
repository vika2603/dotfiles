zmod aliases --after core

zmod:aliases() {
  (( $+commands[eza] )) && alias ls='eza -bh --icons --hyperlink'
  (( $+commands[bat] )) && alias cat='bat --plain'

  alias l='ls -l'    ll='ls -la'   lt='ls --tree'

  alias -g ...='../..'
  alias -g ....='../../..'
  alias -g .....='../../../..'
  alias -g ......='../../../../..'

  alias rm='rm -i'   rd='rmdir'    md='mkdir -p'
  alias cp='cp -v'   mv='mv -v'
  alias df='df -h'   du='du -h'    dus='du -sh'   dusa='dus --apparent-size'

  alias grep='command grep --colour=auto --binary-files=without-match'

  alias reload="exec $SHELL -l"
  alias plast='last -20'
  alias ts='date +%s'

  alias v='nvim'
  return 0
}
