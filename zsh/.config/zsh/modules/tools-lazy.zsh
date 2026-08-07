# 提示符之后再初始化的工具，缺失时静默跳过。
zmod tools-lazy --after tools --phase defer

zmod:tools-lazy() {
  eval "$(pathctl activate)" 2>/dev/null
  eval "$(zoxide init zsh)" 2>/dev/null
  (( $+commands[atuin] )) && eval "$(atuin init zsh --disable-up-arrow)" 2>/dev/null
  return 0
}
