# fpath 的唯一归属地。任何补全目录都应该在这里加，或声明 --before completion。
zmod fpath --after core

zmod:fpath() {
  fpath=($ZDOTDIR/functions $ZDOTDIR/completions $fpath)
  [[ -d /opt/homebrew/share/zsh/site-functions ]] && \
    fpath=(/opt/homebrew/share/zsh/site-functions $fpath)

  # autoload 只登记，真正解析发生在调用时——所以 fpath 必须先稳定。
  autoload -Uz $ZDOTDIR/functions/*(N-.:t)
}
