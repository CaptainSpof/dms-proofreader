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
  is the editor, hosted by both the slideout and
  [ProofreaderWindow.qml](plugin/components/ProofreaderWindow.qml) (the
  detached window). The persisted `mode` decides which one the pill reopens.
- [plugin/components/RichList.qml](plugin/components/RichList.qml) does the
  bullet-list edits as pure functions over the editor's HTML.
- Per-machine defaults come from an optional `proofreader.json` (written by
  [nix/home-module.nix](nix/home-module.nix)); the plugin settings override it.

## Rules

- **Sibling QML types need `components/` + `qmldir` + `import "./components"`.**
  DMS loads plugins from a `?revision=N` URL, which defeats implicit directory
  imports.
- **Never write `Child { host: host }`** (or `ctl: ctl`) when the child
  declares a property of that name: the right-hand side resolves to the
  child's own, unset property. Hence `slideoutWindow` and `win.ctl`.
- **The editor is rich text; LanguageTool sees its plain projection.**
  Document positions map 1:1 onto `getText()`, but Qt returns `<br>` as U+2028
  and paragraph breaks as U+2029: normalise both to `\n` before checking,
  translating or copying. Write them as `\u2028` escapes — a raw U+2028 in a
  QML regex is a line terminator and breaks the parse.
- **LanguageTool offsets are UTF-16 code units**, like QML strings. Never
  convert them.
- **Lists are edited by rebuilding the HTML.** QML has no QTextCursor, and
  `TextEdit.insert()` of a list fragment always starts a new list and merges
  its first item into the current block. So Shift+Return, the list button and
  the plain-text bullet conversion after a paste parse `TextEdit.text` into one
  block per paragraph, edit that and assign it back, which clears the undo
  history. Qt drops an empty `<li></li>`: write `<br />` plus
  `-qt-paragraph-type:empty`. HTML pastes keep their lists natively.
- **Right click goes to `DContextMenu`**, through a right-button `MouseArea`
  over the `TextArea`, as in the DMS Notepad; otherwise Qt shows its own,
  unthemed menu.
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
- `RichList.qml` only imports QtQml: test it against a real `TextEdit` with
  `qmltestrunner` from nixpkgs' `qtdeclarative`, with `QT_QPA_PLATFORM=offscreen`
  and `QML_IMPORT_PATH` set to its `lib/qt-6/qml`.
- `nix flake check` builds dms-translate and checks a direct pair, a pair
  chained through English, and `--pairs`.
