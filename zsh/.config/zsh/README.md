# zsh 配置

`.zshrc` 只做两件事：加载 `lib/zmod.zsh`，调用 `zmod::load`。真正的配置在 `modules/`。

加载顺序由**依赖声明**算出，和文件名无关。改文件名不会改变行为。

## 模块长什么样

```zsh
# modules/completion.zsh
zmod completion --after plugins --phase defer

zmod:completion() {
  compinit
  ...
}
```

声明参数：

| 参数 | 含义 |
|---|---|
| `--after A,B` | 排在 A、B 之后 |
| `--before C` | 排在 C 之前 |
| `--phase sync` | 提示符渲染前执行（默认） |
| `--phase defer` | 交给 zsh-defer，zle 空闲时执行 |

`sync` 模块不能依赖 `defer` 模块，声明了会报错。

## 两条强制不变量

**1. compinit 是 fpath 的截止线。** `completion` 模块跑完后 fpath 被封存，之后任何模块再改 fpath，其补全都不会注册。`zmod::check_fpath` 会在启动末尾报错并指出是哪个目录。

需要加补全目录的模块必须声明 `--before completion`，`modules/forgit-completion.zsh` 就是范例。

**2. 依赖必须存在且无环。** 违反时不会让 shell 变砖：报错后退回声明顺序继续加载，`zdoctor` 会显示「降级模式」。

## 怎么加东西

**加一个同步初始化的工具** — 编辑 `modules/tools.zsh`，或新建模块 `--after core`。

**加一个不急的工具** — 编辑 `modules/tools-lazy.zsh`，或新建模块 `--phase defer --after tools`。

**加一个补全目录** — 新建模块，声明 `--before completion`：

```zsh
zmod foo-completion --before completion --phase defer
zmod:foo-completion() { fpath=($SOME_DIR/completions $fpath) }
```

**加一个静态补全文件** — 直接扔进 `completions/`，`fpath` 模块已经把它加进 fpath 了，不用改代码。

**加一个插件** — 在 `.zsh_plugins.txt` 加一行（用 `kind:clone`），再在 `modules/plugins.zsh` 的列表里加一项。

**加一个可被环境覆盖的变量** — 用 `zmod::env_default VAR 值`，别用 `export VAR=${VAR:-值}`。后者一旦被父 shell export 过旧值，`exec zsh` 永远取不到新默认值；前者会被 `zdoctor` 检查出来。

## 排查

```sh
zdoctor              # 模块图、不变量、补全抽查、环境变量、缓存状态
ZSH_TRACE=1 exec zsh # 每个模块的耗时
```

改完配置后 `exec zsh`。两种情况 `exec zsh` **不够**，需要开全新终端：

- 改了 `zmod::env_default` 的默认值（旧值已被 export，会被继承）
- 需要重建补全表时：`rm -f $ZDOTDIR/.zcompdump && exec zsh`

派生产物会自动重建，不用手动清：carapace 缓存（签名比对）、antidote bundle（`.zsh_plugins.txt` 更新时）。

## 目录

```
.zshrc              入口，两行
lib/zmod.zsh        模块注册、依赖解析、分相位加载
modules/            配置本体，每个文件一个模块
functions/          autoload 函数，含 zdoctor
completions/        静态补全文件
bin/                加进 PATH 的脚本
abbreviations       zsh-abbr 的缩写定义
.zsh_plugins.txt    antidote 的插件清单
```
