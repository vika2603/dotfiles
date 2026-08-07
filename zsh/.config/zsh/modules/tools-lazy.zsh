# Tools initialised after the prompt; skipped silently when absent.
#zmod after=tools phase=defer

eval "$(pathctl activate)" 2>/dev/null
eval "$(zoxide init zsh)" 2>/dev/null
(( $+commands[atuin] )) && eval "$(atuin init zsh --disable-up-arrow)" 2>/dev/null

# The last statement above is an optional step; without this the module would
# report failure whenever it is legitimately skipped.
return 0
