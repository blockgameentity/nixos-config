# Edit before deploying. Never put secret VALUES in this file.
{ ... }: {
  assertions = [{ assertion = false; message = "Configure local.nix: SSH access, sudo password file, and application image digests; then remove this assertion."; }];
  users.users.desu.openssh.authorizedKeys.keys = [ ];
  users.users.desu.hashedPasswordFile = "/var/lib/secrets/desu-password-hash";
  desu.images.overleaf = "rigon/sharelatex-full:latest-shell-escape";
  desu.images.ttml = "localhost/ttml-fixer:migration";
}
