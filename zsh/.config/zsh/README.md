# zsh config

`.zshrc` does two things: source `lib/zmod.zsh` and call `zmod::load`. The real
configuration lives in `modules/`.

Load order is derived from **dependency declarations**. Any two modules with a
dependency between them keep that order regardless of filename. Modules with no
declared relationship fall back to the order the files are read in, so renaming
can still reorder unrelated modules — if the order matters, declare it.

## What a module looks like

```zsh
# modules/completion.zsh
#zmod after=plugins phase=defer

compinit
...
```

The file is the module and the filename is its name. The header describes only
when it runs; the loader reads headers, resolves the graph, then sources files
in the resolved order.

| Key | Meaning |
|---|---|
| `after=A,B` | run after A and B |
| `before=C` | run before C |
| `phase=sync` | run before the prompt renders (default) |
| `phase=defer` | hand to zsh-defer, runs when zle is idle |

Alias expansion is disabled while a module is sourced, so module code behaves
like a script rather than inheriting `rm -i`, `grep --colour` and friends.

`source` reports only a file's last command, so it cannot prove a module
succeeded throughout: write fatal steps as `cmd || return 1`.

A `sync` module may not depend on a `defer` module; declaring it is an error.

## Two enforced invariants

**1. compinit is the fpath deadline.** Once the `completion` module finishes,
fpath is sealed. Anything added later is never scanned, so those completions are
never registered. `zmod::check_fpath` reports the offending directory at startup.

Modules that add a completion directory must declare `before=completion`.
`modules/forgit-completion.zsh` is the worked example.

**2. Dependencies must exist and be acyclic.** A violation does not brick the
shell: the loader reports the error, falls back to declaration order, and
`zmods` shows `DEGRADED`.

## How to add things

**A tool needed before the prompt** — edit `modules/tools.zsh`, or add a module
with `after=core`.

**A tool that can wait** — edit `modules/tools-lazy.zsh`, or add a module with
`after=tools phase=defer`.

**Anything that tests `$+commands[x]` for a mise-provided tool** — declare
`after=tools`, otherwise the test runs before `mise activate` has put the tool
on PATH and silently takes the false branch. For a conditional alias use
`zmod::alias_if` so the mistake is reported rather than silent.

**A completion directory** — new module declaring `before=completion`:

```zsh
# modules/foo-completion.zsh
#zmod before=completion phase=defer

fpath=($SOME_DIR/completions $fpath)
```

**A static completion file** — drop it in `completions/`. The `fpath` module
already has that directory on fpath; no code change needed.

**A plugin** — add a line to `.zsh_plugins.txt` (use `kind:clone`), then add it
to the list in `modules/plugins.zsh`.

**A variable the environment may override** — use `zmod::env_default VAR value`,
not `export VAR=${VAR:-value}`. The latter is sticky: once a parent shell has
exported the old default, `exec zsh` inherits it and the new default never
applies. `zmod::env_default` warns the moment it detects one.

## Troubleshooting

```sh
zmods                # module graph, order, status and timings
ZSH_TRACE=1 exec zsh # per-module timings
```

There is no health command. Everything announces itself when it happens:

- dependency errors and module failures print at load
- `zmod::verify` runs after every module and reports fpath violations and any
  `zmod::alias_if` declaration whose command is on PATH but whose alias was
  never defined
- `zmod::env_default` warns when an inherited value blocks the configured one

That last pair is why those helpers exist. A bare `(( $+commands[x] )) && alias`
that never fires cannot be told apart from one nobody wanted, and the alias
check has to run after every module — the failure it guards against is a module
running *before* the one that puts the command on PATH, so a check at the same
moment would legitimately see the command as absent.

`exec zsh` picks up most changes. Two cases need a brand new terminal:

- a changed `zmod::env_default` value (the old one is already exported and inherited)
- rebuilding the completion table: `rm -f $ZDOTDIR/.zcompdump && exec zsh`

Derived artifacts rebuild themselves: the carapace cache (signature comparison)
and the antidote bundle (when `.zsh_plugins.txt` is newer).

## Layout

```
.zshrc              entry point, two lines
lib/zmod.zsh        header parsing, dependency resolution, phased loading
modules/            the configuration itself, one module per file
functions/          autoloaded functions, including zmods
completions/        static completion files
bin/                scripts added to PATH
abbreviations       zsh-abbr definitions
.zsh_plugins.txt    antidote plugin manifest
```
