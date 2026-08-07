# forgit 的补全目录只有插件 source 之后才知道路径（$FORGIT_INSTALL_DIR），
# 但必须赶在 compinit 扫描 fpath 之前加进去。这两个约束就是下面两行声明。
# 之前这里写在 compinit 后面，_git-forgit 从未注册，且不报错。
zmod forgit-completion --after plugins --before completion --phase defer

zmod:forgit-completion() {
  [[ -n $FORGIT_INSTALL_DIR ]] || return 0
  fpath=($FORGIT_INSTALL_DIR/completions $fpath)
}
