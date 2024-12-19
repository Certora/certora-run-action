{ buildGoModule, fetchFromGitHub, }:

buildGoModule rec {
  pname = "jc21";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "jc21";
    repo = "json-strip-comments";
    rev = "v${version}";
    hash = "sha256-ueqjX6Elqs9Kwj2BICy1isTN644JR4w22NtPRI+qXhY=";
  };

  vendorHash = "sha256-WcWuald1sZKFcPbG1PP7BZN5AaTk3UzkhIIGHnNQTzU=";

  ldflags = [ "-s" "-w" ];

  meta = {
    homepage = "https://github.com/jc21/json-strip-comments";
    description =
      "This is a very simple command that will remove comments from JSON files.";
    mainProgram = "json-strip-comments";
  };
}
