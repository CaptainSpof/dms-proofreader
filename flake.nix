{
  description = "Spelling, grammar and offline translation scratchpad for DankMaterialShell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # translateLocally (Bergamot) is only exercised on x86_64-linux.
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        dms-translate = pkgs.callPackage ./nix/dms-translate.nix { };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.dms-translate;
      });

      homeModules = {
        dms-proofreader = import ./nix/home-module.nix self;
        default = self.homeModules.dms-proofreader;
      };

      checks = forAllSystems (
        pkgs:
        let
          dms-translate = self.packages.${pkgs.stdenv.hostPlatform.system}.dms-translate;
        in
        {
          # A direct pair, a pair chained through English, and the pair list.
          translate = pkgs.runCommand "dms-translate-check" { nativeBuildInputs = [ dms-translate ]; } ''
            [ "$(dms-translate fr en Bonjour)" = Hello ]
            [ -n "$(dms-translate de fr 'Guten Morgen')" ]
            dms-translate --pairs | grep -q '"fr":\['
            touch $out
          '';
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
