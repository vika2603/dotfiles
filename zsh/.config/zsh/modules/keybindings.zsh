# 绑定用到 _fancy_ctrl_z / _sudo_prepend，两者由 fpath 模块 autoload。
zmod keybindings --after fpath

zmod:keybindings() {
  bindkey -e
  KEYTIMEOUT=1
  autoload -Uz up-line-or-beginning-search down-line-or-beginning-search edit-command-line
  zle -N up-line-or-beginning-search
  zle -N down-line-or-beginning-search
  zle -N edit-command-line
  zle -N _fancy_ctrl_z
  zle -N _sudo_prepend

  bindkey "$terminfo[khome]"  beginning-of-line
  bindkey "$terminfo[kend]"   end-of-line
  bindkey "$terminfo[kdch1]"  delete-char
  bindkey "$terminfo[kcuu1]"  up-line-or-beginning-search
  bindkey "$terminfo[kcud1]"  down-line-or-beginning-search
  bindkey '^[[1;5C'           forward-word
  bindkey '^[[1;5D'           backward-word
  bindkey '^w'                backward-kill-word
  bindkey '^d'                delete-char
  bindkey '^o'                edit-command-line
  bindkey '^[q'               push-line-or-edit
  bindkey ' '                 magic-space
  bindkey '^Z'                _fancy_ctrl_z
  bindkey '^[^['              _sudo_prepend
  bindkey '^[[109;5u'         accept-line
  bindkey '^[[27;2;13~'       accept-line
}
