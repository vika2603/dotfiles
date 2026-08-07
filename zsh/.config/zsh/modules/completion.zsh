# compinit 在这里运行，是 fpath 的截止线：之后再改 fpath 的补全都不会注册。
# 需要加补全目录的模块声明 --before completion。
zmod completion --after plugins --phase defer

zmod:completion() {
  zmodload zsh/complist
  autoload -Uz compinit
  compinit
  _comp_options+=(globdots)

  # fzf-tab 必须在 compinit 之后加载。它会把自己的 lib 加进 fpath——那是
  # ftb-* autoload 函数，不是补全，所以封存点放在它之后。
  source $ANTIDOTE_HOME/github.com/Aloxaf/fzf-tab/fzf-tab.plugin.zsh
  _fsh_theme

  # 此后任何模块再改 fpath，其补全都不会被注册，zmod::check_fpath 会报错。
  zmod::seal_fpath
  return 0
}
