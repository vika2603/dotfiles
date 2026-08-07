# forgit's completion path is only known after the plugin is sourced
# ($FORGIT_INSTALL_DIR), yet it must land in fpath before compinit scans it.
# Those two constraints are exactly the declaration below. This used to run
# after compinit, so _git-forgit was never registered and nothing reported it.
zmod forgit-completion --after plugins --before completion --phase defer

zmod:forgit-completion() {
  [[ -n $FORGIT_INSTALL_DIR ]] || return 0
  fpath=($FORGIT_INSTALL_DIR/completions $fpath)
}
