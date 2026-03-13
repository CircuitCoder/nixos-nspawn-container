# nixos-nspawn-container

These scripts creates a systemd-nspawn container from a initial NixOS configuration, whose daemon and store is shared with the host. This is useful for spawning multiple development containers with similar environments, while allowing each one to customize their own environment afterward.

## Usage

Create a configuration file based on the following template:

```nix
{ config, lib, pkgs, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/profiles/minimal.nix>
  ];

  boot.isContainer = true;

  # Daemon socket is bind mounted from the host
  systemd.services.nix-daemon.enable = false;
  systemd.sockets.nix-daemon.enable = false;

  # Store is ro-mounted
  nix.gc.automatic = false;
  nix.optimise.automatic = false;

  # Force commands through the daemon
  environment.variables.NIX_REMOTE = "daemon";

  # Disable some QoL features
  documentation.enable = lib.mkForce false;
  documentation.nixos.enable = lib.mkForce false;
  documentation.man.enable = lib.mkForce false;
  documentation.info.enable = lib.mkForce false;
  documentation.doc.enable = lib.mkForce false;

  system.activationScripts.specialfs = lib.mkForce "";

  # system.stateVersion = "CHANGE ME!";
}
```

Running `create.sh <configuration.nix>` will prints a UUID, which is the ID of the new container. You can now manage the container with `machinectl`. Before starting the container, you may want to edit the generated configuration file at `/etc/systemd/nspawn/<NAME>.nspawn`. Try `machinectl edit <NAME>`.

Things that's not configured by the script but may be desirable:
- Networking and port forward
- PrivateUsers & PrivateUsersOwnership. Because we just created our rootfs with the current user as owner, if we want UID namespace, nspawn needs to chown the rootfs. See [systemd.nspawn doc](https://www.freedesktop.org/software/systemd/man/latest/systemd.nspawn.html#PrivateUsersOwnership=)

Use `systemctl start start systemd-nspawn@<NAME>.service` to start the container. Then you can see it in `machinectl list`.

## Caveats

Since we're binding the daemon socket from the host, we have to disable the daemon in the container.

Also, if your configuration file imports other files, you may need to manually copy / adjust the created configuration file in the rootfs at `/var/lib/machines/<NAME>`.

The guest may not have any channel configured, so the first `nixos-rebuild` may fail. You can add the same channels as the host inside the container, but see the following caveat about the writability of the profile directory. Remember to `nix-channel --update`!

Finally, we're using idmap mounts for the profile directory. This is not supported in older kernels and some filesystems (e.g. ZFS). If you cannot use idmap mounts, remove that from the nspwan config and choose the following options:
- Disable UID namespace
- Chmod 777 on the per-container profile directory from the host.
