# dms-proofreader

DankMaterialShell plugin ([plugin/](plugin)), the `dms-translate` wrapper
([bin/](bin/dms-translate), packaged in [nix/](nix)), and a Home Manager module.
The plugin id is `proofreader`; its saved state lives under that id, so never
rename it.

## Layout

- [plugin/ProofreaderWidget.qml](plugin/ProofreaderWidget.qml) holds all state
  and the LanguageTool / translation calls. The first instance to load (one runs
  per bar per screen) owns the IPC target and the per-screen slideouts; the
  other pills route their clicks to it through a global var.
- [plugin/components/ProofreaderPanel.qml](plugin/components/ProofreaderPanel.qml)
  is the slideout body.
- Per-machine defaults come from an optional `proofreader.json` (written by
  [nix/home-module.nix](nix/home-module.nix)); the plugin settings override it.

## Rules

- **Sibling QML types need `components/` + `qmldir` + `import "./components"`.**
  DMS loads plugins from a `?revision=N` URL, which defeats implicit directory
  imports.
- **Never write `Child { slideout: slideout }`** when the child declares a
  property of that name: the right-hand side resolves to the child's own,
  unset property. The slideout's id is `slideoutWindow` for that reason.
- **The editor is rich text; LanguageTool sees its plain projection.**
  Document positions map 1:1 onto `getText()`, but Qt returns `<br>` as U+2028
  and paragraph breaks as U+2029: normalise both to `\n` before checking,
  translating or copying. Write them as `\u2028` escapes — a raw U+2028 in a
  QML regex is a line terminator and breaks the parse.
- **LanguageTool offsets are UTF-16 code units**, like QML strings. Never
  convert them.
- **Errors are drawn, not highlighted**: Qt Quick has no QML syntax
  highlighter, so underlines are rectangles laid over the `TextArea` from
  `positionToRectangle()`.
- **Bare `en` and `de` have no spell checker** in LanguageTool 6.6 (a typo like
  "hte" passes); only their variants do. They are filtered out of the language
  menu and migrated in saved state. Other bare codes checked spelling when
  surveyed.
- **LanguageTool lists some languages twice under one name** ("French" is
  both `fr` and `fr-FR`). The menu keeps one entry per name — the pinned one,
  else the shortest code — because DankDropdown keys options by label.
- `TextArea.copy()` needs a real input event on Wayland: from IPC it silently
  does nothing, hence the `wl-paste --list-types` check and plain-text fallback.
- nixpkgs' `translatelocally` is overridden with `-Wno-error=array-bounds`
  ([nix/dms-translate.nix](nix/dms-translate.nix)) because it fails under
  gcc 16. Drop the override once nixpkgs builds it again.

## Testing against a running DMS

- Link this `plugin/` over `~/.config/DankMaterialShell/plugins/proofreader`
  (restore the Home Manager link before the next switch).
- Qt caches components: `dms ipc call plugins reload proofreader` after an edit,
  and restart `dms` after a component failed to load once. Edits under
  `components/` are not picked up by the reload either: restart `dms`.
- `PluginService` caches plugin state in memory on first load; a hand-edited
  `~/.local/state/DankMaterialShell/plugins/proofreader_state.json` only takes
  effect after a DMS restart.
- DMS swallows exceptions thrown in handlers. To observe the plugin, write to a
  file with `Quickshell.execDetached` (under `$HOME`, not the agent's `/tmp`).
- `nix flake check` builds dms-translate and checks a direct pair, a pair
  chained through English, and `--pairs`.
