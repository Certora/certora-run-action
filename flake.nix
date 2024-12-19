{
  description = "Certora GitHub Run Action";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        json-strip-comments-overlay = final: prev: {
          json-strip-comments =
            final.callPackage ./nix/json-strip-comments.nix { };
        };

        pkgs = import nixpkgs {
          inherit system;

          overlays = [ json-strip-comments-overlay ];
        };

        test_packages = with pkgs; [ action-validator shellcheck ];

        devShell = with pkgs;
          mkShellNoCC {
            name = "cert-gh-run-action";
            packages = [ act jq gh nodejs pre-commit json-strip-comments ]
              ++ test_packages;

            nativeBuildInputs = [
              # set SOURCE_DATE_EPOCH so that we can use python wheels
              ensureNewerSourcesForZipFilesHook
            ];

          };
        ciShell = with pkgs;
          mkShellNoCC {
            name = "cert-gh-run-action-ci";
            packages = test_packages;
          };
      in {
        devShell = devShell;
        ciShell = ciShell;
        packages = { dev-shell = devShell.inputDerivation; };
      });
}
