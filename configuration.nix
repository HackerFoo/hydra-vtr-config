{ pkgs ? import <nixpkgs> {}, ... }:

with pkgs;
with builtins;
with lib;

# things very specific to this installation
with import ./specifics.nix;

let
  hydraCores = cores * 4; # so localhost can wait on more jobs
  maxDbConnections = builderCount * builderCores + hydraCores;
  unstable = import <nixos-unstable> {};
  my_nix = pkgs: with pkgs; nixUnstable.overrideAttrs (oldAttrs: {
    src = fetchGit {
      url = "https://github.com/NixOS/nix.git";
      ref = "flakes";
      rev = "7db879e65e83b1c65206b490d36a69e97c5a877a";
    };
    buildInputs = oldAttrs.buildInputs ++ [ gmock ];
  });
in
{
  imports = [ <nixpkgs/nixos/modules/virtualisation/google-compute-image.nix> ];

  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "831a6d12";

  security.acme = {
    acceptTerms = true;
    email = contact_email;
  };

  security.sudo.wheelNeedsPassword = false;
  users.extraUsers = extraUsers;

  time.timeZone = "America/Los_Angeles";

  services = {
    # for sending emails (optional)
    postfix = {
      enable = true;
      setSendmail = true;
    };

    # actual Hydra config
    hydra = {
      enable = true;
      hydraURL = "https://${domain}/";
      listenHost = "localhost";
      port = 3000;
      minimumDiskFree = 5;  # in GB
      minimumDiskFreeEvaluator = 2;
      notificationSender = "hydra@localhost"; # TODO
      inherit logo;
      debugServer = false;
      useSubstitutes = false; # too many queries
      package = hydra-unstable.overrideAttrs (attrs: { # override hard-coded defaults
        src = fetchGit {
	  url = "https://github.com/NixOS/hydra.git";
          #rev = "15a45f1a8a867369bb58991fbcf58366b10cc62d"; # to fix mkFlags() build error
	  rev = "1831866a52df4a2821faf902c8440136cdf4c827";
        };
        patches = attrs.patches ++ [ ./hydra-defaults.patch ./always_allow_import_from_derivation.patch ];
	nix = nixFlakes;
      });
      extraConfig = ''
        store_uri = auto?secret-key=/etc/nixos/cache-key-priv.pem
        binary_cache_secret_key_file = /etc/nixos/cache-key-priv.pem
        max_db_connections = ${toString maxDbConnections}
        max_output_size = 2199023255552
        allow_import_from_derivation = true
      '';
    };

    # https://stackoverflow.com/questions/30778015/how-to-increase-the-max-connections-in-postgres
    postgresql.extraConfig = ''
      max_connections = ${toString maxDbConnections}
      shared_buffers = ${toString maxDbConnections}MB
    '';

    # frontend http/https server
    nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      # other Nginx options
      virtualHosts."${domain}" =  {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3000";
          proxyWebsockets = true; # needed if you need to use WebSocket
          extraConfig =
            # required when the target is also TLS server with multiple hosts
            "proxy_ssl_server_name on;" +
            # required when the server wants to use HTTP Authentication
            "proxy_pass_header Authorization;"
            ;
        };
      };
    };
  };

  nix = {
    systemFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" "local" ];
    extraOptions = ''
      allowed-uris = https://github.com ssh://git@github.com
      experimental-features = nix-command
      secret-key-files = /etc/nixos/cache-key-priv.pem
      allow-import-from-derivation = true
    '';
    maxJobs = cores;
    buildCores = cores;
    nrBuildUsers = hydraCores;
    distributedBuilds = true;
    autoOptimiseStore = true;
    buildMachines = let machine = id: {
        hostName = "builder-${toString id}";
	sshUser = "root";
	maxJobs = builderCores;
	system = "x86_64-linux";
	supportedFeatures = [ "kvm" "benchmark" "big-parallel" ];
      };
    in
    [
      {
        hostName = "localhost";
    	sshUser = "root";
    	maxJobs = hydraCores;
    	system = "x86_64-linux";
    	supportedFeatures = [ "kvm" "local" "big-parallel" ];
      }
    ] ++
    map machine (range 0 (builderCount - 1));
    trustedUsers = [ "root" "@wheel" "@hydra" ];
  };

  services.nix-serve.secretKeyFile = "/etc/nixos/cache-key-priv.pem";

  # need the latest nix (for now)
  nixpkgs.overlays = [
    (self: super: {
      # nix = my_nix super;
      nixFlakes = my_nix super;
      # nixUnstable = my_nix super;
    })
  ];

  # zramSwap.enable = true;
  swapDevices = [
    { device = "/swapfile"; }
  ];

  security.pam.loginLimits = [{
    domain = "*";
    type = "soft";
    item = "nofile";
    value = "524288";
  }];

  systemd.extraConfig = ''
    DefaultLimitNOFILE=524288
  '';

  fileSystems."/nix" =
    { device = "rpool/nix";
      fsType = "zfs";
    };
}
