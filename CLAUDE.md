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

## `DMSShell.qml` fails to load — silently

`shell.qml` loads `ShellCore.qml` (which owns `DankBar`), then **async**-loads
`DMSShell.qml`. A compile error in anything `DMSShell.qml` reaches sets
`dmsShellLoader.status = Loader.Error` and **prints nothing** — `qs log` stays clean.

The bars keep rendering, so the shell looks healthy while everything `DMSShell.qml`
owns is dead: every bar popout (dash/date, control centre, notification centre,
notepad, colour picker, app drawer), notification popups, the dock, OSD, the lock
screen, and all ~20 shell IPC targets.

**Symptom to recognise:** left-clicking bar widgets opens nothing, while actions that
need no popout still work (right-click volume still mutes). Easy to misread as a
click-target or z-order problem — it is not.

### Smoke test (one line, deterministic)

```bash
dms ipc 2>&1 | grep -q '^  settings ' && echo "OK: DMSShell loaded" || echo "BROKEN"
```

Only `DMSShellIPC.qml` registers `settings`, `widget`, `notifications`, `dash`,
`control-center`, `dock`, `notepad`, … If those are missing but `theme`, `audio`,
`brightness`, `plugin-scan` are present, `DMSShell.qml` failed: those survivors come
from singleton services (`Theme.qml`, `AudioService.qml`, `PluginService.qml`), which
load independently.

### Getting the actual error

`qmllint` does **not** catch this. It cannot resolve the type graph through the
`quickshell/DankCommon -> ../dank-qml-common/DankCommon` symlink, so it reports the
same 8 `unresolved-alias` and 24 `unresolved-type` warnings whether the tree is broken
or fixed — identical output, zero signal.

Ask QML instead. Run the shell straight from the working tree (no `nix build` needed,
edits are live):

```bash
dms run -d -c ~/code/_forks/DankMaterialShell/quickshell
```

and temporarily add to `shell.qml`'s `dmsShellLoader`:

```qml
onStatusChanged: {
    if (status === Loader.Error) {
        const c = Qt.createComponent("DMSShell.qml");
        console.error("[[PROBE]] " + c.errorString());
    }
}
```

`Qt.createComponent` compiles synchronously and prints the full chain, e.g.

```
DMSShell.qml:680: Type SettingsModal unavailable
 Modals/Settings/SettingsModal.qml:385: Type SettingsContent unavailable
  Modals/Settings/SettingsContent.qml:104: Type DankBarTab unavailable
   Modules/Settings/DankBarTab.qml:774: Type SettingsSliderRow unavailable
    Modules/Settings/Widgets/SettingsSliderRow.qml:60: Invalid alias target location: decimals
```

Read the chain bottom-up: the last line is the real fault, everything above is fallout.

### The 2026-09-07 instance — overridden re-export

Upstream keeps `quickshell/Widgets/DankSlider.qml` as a three-line re-export:

```qml
import qs.DankCommon.Widgets as DankCommon

DankCommon.DankSlider {}
```

The fork's `bb3b4c4b` ("feat: add DDC/CI extended monitor controls") replaced it with a
stale 314-line inline copy predating the `valueDecimals` → `decimals` rename. Upstream's
`SettingsSliderRow.qml:60` aliases `slider.decimals`, which no longer existed, and the
whole of `DMSShell.qml` went down with it. Fork-only: `upstream/master` has zero
`valueDecimals` occurrences, and the `dank-qml-common` submodule pin is identical in
both, so `decimals` was always available there.

Fix was to restore the re-export and rename the two call sites
(`MonitorControlsDetail.qml`, `DDCSettingsTab.qml`) from `valueDecimals:` to `decimals:`.

**Why it matters:** overriding a re-export silently pins that widget's API to whatever
upstream looked like on the day you copied it. Every later upstream rename in
`dank-qml-common` then becomes a shell-wide outage, not a local glitch.

**How to apply:** never inline a file whose upstream version is a `DankCommon.` re-export
— add the property to `dank-qml-common` instead. Check before every build:

```bash
git fetch upstream -q
git diff --name-only upstream/master -- quickshell/ | while read -r f; do
  git show "upstream/master:$f" 2>/dev/null | grep -q 'DankCommon\.' &&
    echo "OVERRIDDEN RE-EXPORT: $f"
done
```

Any output here is the bug about to happen. Empty output is clean.
