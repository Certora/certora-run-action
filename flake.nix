{
  description = "Certora GitHub Run Action";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ ];
        };

        devShell = with pkgs;
          mkShellNoCC {
            name = "cert-gh-run-action";
            packages = [ act jq gh nodejs ];

            nativeBuildInputs = [
              # set SOURCE_DATE_EPOCH so that we can use python wheels
              ensureNewerSourcesForZipFilesHook
            ];

          };
      in {
        devShell = devShell;
        packages = { dev-shell = devShell.inputDerivation; };
      });
}
