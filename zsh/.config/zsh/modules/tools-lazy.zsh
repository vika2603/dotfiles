# Tools initialised after the prompt; skipped silently when absent.
zmod tools-lazy --after tools --phase defer

zmod:tools-lazy() {
  eval "$(pathctl activate)" 2>/dev/null
  eval "$(zoxide init zsh)" 2>/dev/null
  (( $+commands[atuin] )) && eval "$(atuin init zsh --disable-up-arrow)" 2>/dev/null
  return 0
}
