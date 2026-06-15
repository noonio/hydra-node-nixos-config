alias d := deploy

[private]
default:
  @just --list

deploy:
  nixos-rebuild switch \
    --target-host hydra@35.214.9.104 \
    --flake .#noon-hydra \
    --use-remote-sudo
