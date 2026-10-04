{
  lib,
  makeWrapper,
  stdenvNoCC,
  symlinkJoin,
  translatelocally,
  translatelocally-models,
  # Attribute names from translatelocally-models. Bergamot models mostly go to
  # or from English; dms-translate chains the rest through English.
  models ? [
    "fr-en-tiny"
    "en-fr-tiny"
    "de-en-tiny"
    "en-de-tiny"
    "es-en-tiny"
    "en-es-tiny"
  ],
}:

let
  # nixpkgs' translatelocally fails under gcc 16: marian's shared_ptr use
  # trips -Werror=array-bounds, a false positive in libstdc++ headers.
  translatelocally' = translatelocally.overrideAttrs (old: {
    env = (old.env or { }) // {
      NIX_CFLAGS_COMPILE = toString [
        (old.env.NIX_CFLAGS_COMPILE or "")
        "-Wno-error=array-bounds"
      ];
    };
  });

  modelData = symlinkJoin {
    name = "dms-translate-models";
    paths = map (code: translatelocally-models.${code}) models;
  };
in
stdenvNoCC.mkDerivation {
  pname = "dms-translate";
  version = "1.0.0";

  src = ../bin;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -Dm755 dms-translate $out/bin/dms-translate
    wrapProgram $out/bin/dms-translate \
      --set DMS_TRANSLATE_BIN ${lib.getExe translatelocally'} \
      --prefix XDG_DATA_DIRS : ${modelData}/share
    runHook postInstall
  '';

  passthru = {
    inherit models;
    translatelocally = translatelocally';
  };

  meta = {
    description = "Offline translation for the DMS proofreader plugin (translateLocally/Bergamot)";
    license = lib.licenses.asl20;
    mainProgram = "dms-translate";
    platforms = lib.platforms.linux;
  };
}
