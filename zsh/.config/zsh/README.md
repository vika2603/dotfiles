# zsh config

`.zshrc` does two things: source `lib/zmod.zsh` and call `zmod::load`. The real
configuration lives in `modules/`.

Load order is derived from **dependency declarations**, not filenames. Renaming
a module file does not change behaviour.

## What a module looks like

```zsh
# modules/completion.zsh
zmod completion --after plugins --phase defer

zmod:completion() {
  compinit
  ...
}
```

| Argument | Meaning |
|---|---|
| `--after A,B` | run after A and B |
| `--before C` | run before C |
| `--phase sync` | run before the prompt renders (default) |
| `--phase defer` | hand to zsh-defer, runs when zle is idle |

A `sync` module may not depend on a `defer` module; declaring it is an error.

## Two enforced invariants

**1. compinit is the fpath deadline.** Once the `completion` module finishes,
fpath is sealed. Anything added later is never scanned, so those completions are
never registered. `zmod::check_fpath` reports the offending directory at startup.

Modules that add a completion directory must declare `--before completion`.
`modules/forgit-completion.zsh` is the worked example.

**2. Dependencies must exist and be acyclic.** A violation does not brick the
shell: the loader reports the error, falls back to declaration order, and
`zdoctor` shows `DEGRADED`.

## How to add things

**A tool needed before the prompt** — edit `modules/tools.zsh`, or add a module
with `--after core`.

**A tool that can wait** — edit `modules/tools-lazy.zsh`, or add a module with
`--phase defer --after tools`.

**Anything that tests `$+commands[x]` for a mise-provided tool** — declare
`--after tools`, otherwise the test runs before `mise activate` has put the tool
on PATH and silently takes the false branch.

**A completion directory** — new module declaring `--before completion`:

```zsh
zmod foo-completion --before completion --phase defer
zmod:foo-completion() { fpath=($SOME_DIR/completions $fpath) }
```

**A static completion file** — drop it in `completions/`. The `fpath` module
already has that directory on fpath; no code change needed.

**A plugin** — add a line to `.zsh_plugins.txt` (use `kind:clone`), then add it
to the list in `modules/plugins.zsh`.

**A variable the environment may override** — use `zmod::env_default VAR value`,
not `export VAR=${VAR:-value}`. The latter is sticky: once a parent shell has
exported the old default, `exec zsh` inherits it and the new default never
applies. `zmod::env_default` records the intent so `zdoctor` can report the
mismatch.

## Troubleshooting

```sh
zdoctor              # module graph, invariants, completion and alias spot checks,
                     # environment drift, cache freshness
ZSH_TRACE=1 exec zsh # per-module timings
```

`exec zsh` picks up most changes. Two cases need a brand new terminal:

- a changed `zmod::env_default` value (the old one is already exported and inherited)
- rebuilding the completion table: `rm -f $ZDOTDIR/.zcompdump && exec zsh`

Derived artifacts rebuild themselves: the carapace cache (signature comparison)
and the antidote bundle (when `.zsh_plugins.txt` is newer).

## Layout

```
.zshrc              entry point, two lines
lib/zmod.zsh        registration, dependency resolution, phased loading
modules/            the configuration itself, one module per file
functions/          autoloaded functions, including zdoctor
completions/        static completion files
bin/                scripts added to PATH
abbreviations       zsh-abbr definitions
.zsh_plugins.txt    antidote plugin manifest
```
