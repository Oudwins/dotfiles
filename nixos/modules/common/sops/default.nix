{ ... }:

{
  sops = {
    defaultSopsFile = "${../../../secrets/secrets.yaml}";
    validateSopsFiles = false;
    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_master_key" ];
      generateKey = true;
    };
  };
}
