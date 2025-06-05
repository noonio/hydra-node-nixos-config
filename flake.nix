{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Note: Don't forget to update the version in `configuration.nix`.
    cardano-node.url = "github:IntersectMBO/cardano-node/10.1.4";
    mithril.url = "github:input-output-hk/mithril/2450.0";

    # Note: Don't forget to update the version in `configuration.nix` as well.
    hydra.url = "github:cardano-scaling/hydra/0.21.0";

    # interactive systemd
    isd.url = "github:isd-project/isd";
  };


  outputs =
    { self
    , nixpkgs
    , nixos-generators
    , cardano-node
    , hydra
    , mithril
    , isd
    , ...
    }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      # For rebuilding the image once deployed
      nixosConfigurations.noon-hydra = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            system
            cardano-node
            hydra
            mithril
            isd;
        };
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/google-compute-image.nix"
          ./configuration.nix
        ];
      };

      packages."${system}" = {
        # For deploying to GCP
        gce = nixos-generators.nixosGenerate {
          inherit system;
          specialArgs = {
            inherit
              system
              cardano-node
              hydra
              mithril
              isd;
          };
          modules = [
            ./configuration.nix
          ];
          format = "gce";
        };

        # For testing locally
        qemu = nixos-generators.nixosGenerate {
          inherit system;
          specialArgs = {
            inherit
              system
              cardano-node
              hydra
              mithril
              isd;
            diskSize = 20 * 1024;
          };
          modules = [
            ./configuration.nix
          ];
          format = "qcow";
        };
      };
    };


  nixConfig = {
    extra-substituters = [
      "https://cache.iog.io"
      "https://hydra-node.cachix.org"
      "https://cardano-scaling.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "hydra-node.cachix.org-1:vK4mOEQDQKl9FTbq76NjOuNaRD4pZLxi1yri31HHmIw="
      "cardano-scaling.cachix.org-1:QNK4nFrowZ/aIJMCBsE35m+O70fV6eewsBNdQnCSMKA="
    ];
  };
}
