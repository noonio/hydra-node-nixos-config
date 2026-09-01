alias d := deploy

[private]
default:
  @just --list

deploy host="34.153.166.106":
  nixos-rebuild switch \
    --target-host hydra@{{host}} \
    --flake .#noon-hydra \
    --use-remote-sudo
