# dms-proofreader

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) plugin:
a scratch text area that checks spelling and grammar as you type, Grammarly
style, and translates offline.

- **Checks** come from a [LanguageTool](https://languagetool.org) server
  (LGPL, self-hostable). Errors are underlined in place, colour-coded by kind;
  a click applies a suggestion. Misspellings can be ignored or added to a
  personal dictionary.
- **Language** is detected automatically, or picked from the server's list
  (French and English first).
- **Translation** is offline, through
  [translateLocally](https://translatelocally.com) (Bergamot, the engine behind
  Firefox Translations). Pairs without a model of their own are chained through
  English.
- **Formatting**: bold, italic, underline, strikethrough (Ctrl+B/I/U). Copy puts
  both HTML and plain text on the clipboard.
- **Opens like the Notepad**: a full-height slideout on the focused screen,
  expandable, closed with Escape.

The interface is in French.

## Requirements

- DankMaterialShell ≥ 1.7.
- A LanguageTool server. The default URL is `http://127.0.0.1:8081`, which is
  what NixOS' `services.languagetool` listens on. The public
  `https://api.languagetool.org` also works, within its rate limits, and sends
  your text to languagetool.org.
- For translation: `translateLocally` plus its models, and `dms-translate` (in
  [bin/](bin/dms-translate)) on `PATH`.

## Install with Nix (Home Manager)

```nix
# flake.nix
inputs.dms-proofreader = {
  url = "github:CaptainSpof/dms-proofreader";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Import `inputs.dms-proofreader.homeModules.default` next to DankMaterialShell's
own Home Manager module, then:

```nix
programs.dms-proofreader = {
  enable = true;
  # languageToolUrl = "https://languagetool.example.org";
  # translation.models = [ "fr-en-tiny" "en-fr-tiny" ];  # translatelocally-models names
};
```

and run the server on NixOS (512m of heap runs out once several languages are
loaded):

```nix
services.languagetool = {
  enable = true;
  jvmOptions = [ "-Xmx1g" ];
};
```

The module links the plugin, installs `dms-translate` with the chosen models,
writes the per-machine defaults to `~/.config/DankMaterialShell/proofreader.json`
and enables the plugin once. Then add the **Correcteur** widget to a bar.

## Install without Nix

1. Copy or link [plugin/](plugin) to
   `~/.config/DankMaterialShell/plugins/proofreader` and enable it in DMS'
   plugin settings.
2. Run LanguageTool somewhere, and set its URL in the plugin settings if it is
   not `http://127.0.0.1:8081`.
3. For translation, install translateLocally, download models with
   `translateLocally -d <model>`, and put [bin/dms-translate](bin/dms-translate)
   on `PATH` (or set its path in the plugin settings).

## Usage

| Action                       | How                                   |
| ---------------------------- | ------------------------------------- |
| Open / close                 | the bar widget, or `dms ipc proofreader toggle` |
| Check now                    | Ctrl+Enter, or `dms ipc proofreader check` |
| Bold / italic / underline    | Ctrl+B / Ctrl+I / Ctrl+U              |
| Close                        | Escape                                |

A niri binding:

```kdl
Mod+P { spawn "dms" "ipc" "proofreader" "toggle"; }
```

## dms-translate

```bash
dms-translate fr en "Bonjour"       # Hello
echo "Guten Morgen" | dms-translate de fr
dms-translate --pairs               # {"de":["en","es","fr"],...}
```

Exit code 2 means no installed model covers the pair.

## License

Apache 2.0.
