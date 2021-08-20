let
  pkgs = import (builtins.fetchGit rec {
    name = "dapptools-${rev}";
    url = https://github.com/dapphub/dapptools;
    rev = "afbb707102baa77eac6ad70873fcd3c59a2ff53c";
  }) {};

in
  pkgs.mkShell {
    src = null;
    name = "funding-contracts";
    buildInputs = with pkgs; [
      pkgs.dapp
    ];
  }
