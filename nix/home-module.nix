# Home Manager module. Needs DankMaterialShell's own module
# (programs.dank-material-shell) imported alongside it.
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.dms-proofreader;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  pluginSettingsFile = "${config.xdg.configHome}/DankMaterialShell/plugin_settings.json";
in
{
  options.programs.dms-proofreader = {
    enable = mkEnableOption "the DMS proofreader widget (LanguageTool checks, offline translation)";

    languageToolUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:8081";
      example = "https://api.languagetool.org";
      description = ''
        LanguageTool server to check against. The default matches NixOS'
        `services.languagetool`. A non-empty URL in the plugin's own settings
        wins over this.
      '';
    };

    translation = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Offer offline translation through dms-translate.";
      };

      models = mkOption {
        type = types.listOf (types.enum (builtins.attrNames pkgs.translatelocally-models));
        default = [
          "fr-en-tiny"
          "en-fr-tiny"
          "de-en-tiny"
          "en-de-tiny"
          "es-en-tiny"
          "en-es-tiny"
        ];
        description = ''
          translatelocally-models to install. Pairs without a model of their
          own are chained through English.
        '';
      };

      package = mkOption {
        type = types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.dms-translate.override {
          inherit (cfg.translation) models;
        };
        defaultText = lib.literalExpression "dms-translate built with `translation.models`";
        description = "The dms-translate package to use.";
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = lib.optional cfg.translation.enable cfg.translation.package;

    programs.dank-material-shell.plugins.proofreader.src = "${self}/plugin";

    # Per-machine defaults for the plugin. Its own settings (plugin_settings.json)
    # stay runtime-owned and override these.
    xdg.configFile."DankMaterialShell/proofreader.json".text = builtins.toJSON {
      inherit (cfg) languageToolUrl;
      translateBin = if cfg.translation.enable then lib.getExe cfg.translation.package else "";
      wlPasteBin = lib.getExe' pkgs.wl-clipboard "wl-paste";
    };

    # Plugin enable-state is runtime-owned by DMS; seed it once so the widget
    # works on first login, then leave the toggle to the DMS UI.
    home.activation.dmsProofreaderPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings=${lib.escapeShellArg pluginSettingsFile}
      run mkdir -p "$(dirname "$settings")"
      [ -f "$settings" ] || run sh -c "echo '{}' > \"$settings\""
      if [ "$(${lib.getExe pkgs.jq} -r 'has("proofreader")' "$settings")" != "true" ]; then
        tmp=$(mktemp)
        ${lib.getExe pkgs.jq} '.proofreader = { "enabled": true }' "$settings" > "$tmp" \
          && run mv "$tmp" "$settings"
      fi
    '';
  };
}
