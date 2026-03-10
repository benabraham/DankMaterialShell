@AGENTS.md

# DankMaterialShell — project notes

## Nix build & new files

`nix build .#dms-shell` copies the repo via git's index: modified tracked files are
included, but **untracked new files are silently omitted** (build succeeds, runtime
breaks — e.g. `X is not a type` QML crash-loop on shell start).

**Why:** flakes in a git repo source only what git knows about, like `git archive`.

**How to apply:** after creating any new file (QML, Go, …), run `git add -N <file>`
before `nix build`. Mirror problem: deleted files keep shipping until the deletion
is staged.
