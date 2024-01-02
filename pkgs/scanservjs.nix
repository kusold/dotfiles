{ lib, buildNpmPackage, fetchFromGitHub, pkgs }:

buildNpmPackage rec {
  pname = "scanservjs";
  version = "3.0.3";
  nodejs = pkgs.nodejs_18;

  src = fetchFromGitHub {
    owner = "sbs20";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-aEChnh3EcaVkPwhzaAy+H/xhRKQn5o0sWBSRRmqv+RI=";
  };

  npmDepsHash = "sha256-zUlIwsnvlTmBwQ9GBOqUaov8M4H95SBpzOtQHOzE+sc=";

  # The prepack script runs the build script, which we'd rather do in the build phase.
  npmPackFlags = [ "--ignore-scripts" ];

  NODE_OPTIONS = "--openssl-legacy-provider";

  meta = with lib; {
    description = "SANE scanner nodejs web ui";
    homepage = "https://sbs20.github.io/scanservjs/";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ kusold ];
  };
}