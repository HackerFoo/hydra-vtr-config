{ ... }:

let cores = 96;
in
{
  imports = [ <nixpkgs/nixos/modules/virtualisation/google-compute-image.nix> ];
  nix.maxJobs = cores;
  nix.buildCores = cores;
  nix.nrBuildUsers = cores;

  security.pam.loginLimits = [{
    domain = "*";
    type = "soft";
    item = "nofile";
    value = "524288";
  }];

  systemd.extraConfig = ''
    DefaultLimitNOFILE=524288
  '';
}
