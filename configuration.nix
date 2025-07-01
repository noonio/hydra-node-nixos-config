{ config
, pkgs
, lib
, system
, cardano-node
, hydra
, mithril
, isd
, ...
}:

let
  cardanoDataPath = "/home/hydra/cardano-data";

  # Select only the friends we want from the full list:
  # <https://github.com/input-output-hk/hydra-team-config/tree/master/parties>
  peers = [
    # "dan"
    "franco"
    "sasha"
    # "sebastian"
  ];

  nodeId = "noon";
  hydraPort = "5005";
  # The public IP of this machine; needed so I can advertise my location to
  # other nodes.
  publicIp = "35.214.9.104";

  # This is used to get the script tx id, and should then agree with the
  # version that comes in via the flake input.
  hydraVersion = "0.22.2";

  # These three variables must agree
  networkName = "preview";
  networkMagic = "2";
  # This is it's own var, as mithril calls "preprod" `release-preprod`
  # and "preview" `testing-preview`
  mithrilDir = "testing-${networkName}";

  nodeVersion = "10.1.4"; # Note: This must match the node version in the flake.nix

  commonEnvVars = {
    "CARDANO_NODE_NETWORK_ID" = "${networkMagic}";
    "CARDANO_NODE_SOCKET_PATH" = "${cardanoDataPath}/node.socket";
  };
in
{
  system.stateVersion = "24.05";

  # Incase we want to do some nixing
  nix = {
    settings.trusted-users = [ "root" "hydra" ];
    extraOptions = ''
      experimental-features = nix-command flakes ca-derivations
    '';
  };

  services.openssh = {
    settings.PasswordAuthentication = false;
    enable = true;
  };

  users.users.hydra = {
    isNormalUser = true;
    description = "hydra";
    extraGroups = [ "systemd-journal" "wheel" ];
    initialPassword = ""; # No password

    # Your ssh key
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIATz/Jv+AnBft+9Q01UF07OydvgTTaTdCa+nMqabkUNl" # noonio
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBJd9BiDoUNl0pCVDeIKnlwJu6oOmLIz7l3Ct7xoYjBS" # noonio
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEMuBv9vXsKsOsjS7B6zMOpuLw+gGGHR6hADuTeiNfKO" # locallycompact
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFkv5iajnUL4PiRREbtN4/vM+mX+9IvgKcgnwnmSoNik" # v0d1ch
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBtamRlrHLKLzr8Pcm3qEgdbJh7vCjMO4tm0wbW3REYL" # ffakenz
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDHRjFKHOS4lOw907VWvDMrx/XawRMV2wyc+VSbA4YHnG2ecv6y/JT3gBjmdNw0bgltgQqeBBG/iTciio+Zax8I36rPWMEomDvpgq8B7i1L23eWoK9cKMqYNAUpIAfManhJKvZfBjJ9dRLz4hfUGo2Gah5reuweFrkzWGb2zqILNXoM2KowlkqMOFrd09SgP52sUuwNmaCJaPba7IdqzLqxotWaY420Msd5c8B2l/0E/hNgRu6m5qbZpidmQQJsTk2tq4CWP5xB2SbgEwAuZZ6AUOn2IqGfF8bkLfwHb5qdtss0jxZm47s5Fag9T9MzzbXCAHEdyO01+q83FKIxkiW/" # ch1bo
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.getty.autologinUser = "hydra";

  environment.systemPackages =
    let
      genHydraKey = pkgs.writeShellScriptBin "genHydraKey" ''
        set -e

        if [ -f ${nodeId}-hydra.sk ]; then
          echo "Found a hydra secret key for ${nodeId}; not generating another one."
          exit 0
        fi

        ${hydra.packages."${system}".hydra-node}/bin/hydra-node \
          gen-hydra-key \
            --output-file ${nodeId}-hydra
      '';

      genSomeCardanoKey = script: name: pkgs.writeShellScriptBin script ''
        if [ -f ${nodeId}-${name}.sk ]; then
          echo "Found a ${name} key for ${nodeId}; not generating another one."
          exit 0
        fi

        ${lib.getExe cardano-node.packages.${system}.cardano-cli} address key-gen \
          --verification-key-file ${nodeId}-${name}.vk \
          --signing-key-file ${nodeId}-${name}.sk
      '';

      genCardanoKey = genSomeCardanoKey "genCardanoKey" "node";
      genFundsKey = genSomeCardanoKey "genFundsKey" "funds";
    in
    [
      pkgs.git
      pkgs.jq
      pkgs.websocat
      pkgs.vim
      pkgs.systemctl-tui
      pkgs.tree
      pkgs.lsof

      # New requirement
      pkgs.etcd

      # So you can just do (if you just want fresh credentials):
      #
      #  > cd ~/cardano-data/credentials
      #  > genHydraKey
      #  > genCardanoKey
      #  > genFundsKey
      #
      genHydraKey
      genCardanoKey
      genFundsKey

      # interactive systemd
      isd.packages."${system}".default

      hydra.packages."${system}".hydra-tui # To interact with your node/peers
      hydra.packages."${system}".hydraw # To play hydraw

      # These aren't really needed, as the systemd services just pull in the
      # binaries directly, but might be useful for debugging, so we leave them
      # in the system path.
      hydra.packages."${system}".hydra-node # To run a hydra node
      cardano-node.packages."${system}".cardano-node # To talk to the cardano network
      mithril.packages."${system}".mithril-client-cli # Efficient syncing of the cardano node
      cardano-node.packages."${system}".cardano-cli # For any ad-hoc cardano actions we may like to run
    ];

  programs.bash.shellAliases = {
    # Run 'logs -f' to follow
    logs = "journalctl -u mithril-maybe-download -u cardano-node -u hydra-node -u necessary-files";

    # Open hydra-tui with the right args:
    tui = "hydra-tui --testnet-magic ${networkMagic} --node-socket ${cardanoDataPath}/node.socket -k ${cardanoDataPath}/credentials/${nodeId}-funds.sk";

    # Start/stop hydra-node
    start-node = "sudo systemctl start hydra-node";
    stop-node = "sudo systemctl stop hydra-node";
  };

  environment.variables = commonEnvVars;

  systemd.services = {
    necessary-files = {
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "mithril-maybe-download.target" ];
      path = with pkgs; [
        curl
        gnutar
        gzip
        git
        cardano-node.packages."${system}".cardano-cli
      ];
      serviceConfig = {
        User = "hydra";
        Type = "notify";
        NotifyAccess = "all";
        ExecStart =
          let
            necessaryFiles = pkgs.writeShellScriptBin "necessaryFiles" ''
              set -e

              if [ -d ${cardanoDataPath} ]; then
                echo "Not re-creating configs because ${cardanoDataPath} exists."
                systemd-notify --ready
                exit 0
              fi

              mkdir -p ${cardanoDataPath}/credentials

              cd ${cardanoDataPath}

              # Get the node configs
              curl -L -O \
                https://github.com/IntersectMBO/cardano-node/releases/download/${nodeVersion}/cardano-node-${nodeVersion}-linux.tar.gz

              tar xf cardano-node-${nodeVersion}-linux.tar.gz \
                  ./share/${networkName} \
                  --strip-components=3

              # Get our hydra config (and peer config)
              git clone https://github.com/cardano-scaling/hydra-team-config.git

              # Jump to specific revision
              cd hydra-team-config && \
                git checkout fae9724275bec9f3766936b40cd3bd2c56031b78 && \
                cd ..

              systemd-notify --ready
            '';
          in
          "${lib.getExe necessaryFiles}";
      };
    };


    mithril-maybe-download =
      let
      in
      {
        requires = [ "network-online.target" "necessary-files.service" ];
        after = [ "necessary-files.service" ];
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [ curl ];
        serviceConfig = {
          Type = "notify";
          NotifyAccess = "all";
          User = "hydra";
          WorkingDirectory = cardanoDataPath;
          Environment = [
            "AGGREGATOR_ENDPOINT=https://aggregator.${mithrilDir}.api.mithril.network/aggregator"
          ];
          # We need to wait a bit for the initial download.
          TimeoutStartSec = 30 * 60;
          ExecStart =
            let
              mithrilMaybeDownload = pkgs.writeShellScriptBin "mithrilMaybeDownload" ''
                set -e

                export GENESIS_VERIFICATION_KEY=''$(curl https://raw.githubusercontent.com/input-output-hk/mithril/main/mithril-infra/configuration/${mithrilDir}/genesis.vkey 2> /dev/null)

                if [ ! -d db ]; then
                  ${mithril.packages.${system}.mithril-client-cli}/bin/mithril-client \
                    cardano-db \
                    download \
                    latest
                fi

                systemd-notify --ready
              '';
            in
            "${lib.getExe mithrilMaybeDownload}";
        };
      };

    cardano-node = {
      requires = [ "mithril-maybe-download.service" "necessary-files.service" ];
      after = [ "mithril-maybe-download.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "hydra";
        WorkingDirectory = cardanoDataPath;
        ExecStart = ''${lib.getExe cardano-node.packages.${system}.cardano-node} \
                run \
                --config config.json \
                --topology topology.json \
                --socket-path ${cardanoDataPath}/node.socket \
                --database-path db
        '';
        # We have to make a list here; this field doesn't support an attrset.
        Environment = lib.attrsets.mapAttrsToList (k: v: "${k}=${v}") commonEnvVars;
        Restart = "on-failure";
      };
    };


    hydra-node = {
      after = [ "cardano-node.service" ];
      requires = [ "cardano-node.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ git jq etcd ];
      serviceConfig = {
        User = "hydra";
        WorkingDirectory = cardanoDataPath;
        # Wait 10 minutes before restarting
        RestartSec = 1 * 60;
        Environment = [
          "ETCD_AUTO_COMPACTION_MODE=periodic"
          "ETCD_AUTO_COMPACTION_RETENTION=168h"
        ];
        ExecStart =
          let
            peerArgs =
              let
                dir = "hydra-team-config/parties";
                f = name: lib.strings.concatStringsSep " "
                  [
                    "--peer $(cat ${dir}/${name}.peer)"
                    "--hydra-verification-key ${dir}/${name}.hydra.vk"
                    "--cardano-verification-key ${dir}/${name}.cardano.vk"
                  ];
              in
              pkgs.lib.strings.concatMapStringsSep " " f peers;
            spinupHydra = pkgs.writeShellScriptBin "spinupHydra" ''
              ${hydra.packages.${system}.hydra-node}/bin/hydra-node \
                --node-id ${nodeId} \
                --cardano-signing-key credentials/${nodeId}-node.sk \
                --hydra-signing-key credentials/${nodeId}-hydra.sk \
                --api-host 0.0.0.0 \
                --listen 0.0.0.0:${hydraPort} \
                --advertise ${publicIp}:${hydraPort} \
                --testnet-magic ${networkMagic}  \
                --node-socket node.socket \
                --persistence-dir persistence \
                --ledger-protocol-parameters hydra-team-config/protocol-parameters.json \
                --contestation-period 300s \
                --deposit-period 600s \
                --monitoring-port 9009 \
                --persistence-rotate-after 10000 \
                --network ${networkName} \
                ${peerArgs}
            '';
          in
          "${lib.getExe spinupHydra}";

        Restart = "on-failure";
      };
    };
  };
}
