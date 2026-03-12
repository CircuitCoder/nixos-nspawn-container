# nixos-nspawn-container

These scripts creates a systemd-nspawn container from a initial NixOS configuration, whose daemon and store is shared with the host. This may be benifitial for spawning multiple development containers with similar environments, but allowing each one to customize their own environment afterward.

## Usage

Create a configuration file based on the following template:

```nix
{ config, pkgs, ... }:

{
  boot.isContainer = true;

  # Daemon socket is bound mounted from the host
  systemd.services.nix-daemon.enable = false;
  systemd.sockets.nix-daemon.enable = false;

  # Store is ro-mounted
  nix.gc.automatic = false;
  nix.optimise.automatic = false;

  # Force commands through the daemon
  environment.variables.NIX_REMOTE = "daemon";
}
```

Running `create.sh <configuration.nix>` will prints a UUID, which is the ID of the new container. You can now manage the container with `machinectl`. Try `machinectl list`. Before starting the container, you may want to edit the generated configuration file at `/etc/systemd/nspawn/<NAME>.nspawn`.