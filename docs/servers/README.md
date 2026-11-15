> Moved here from the former `servers` repo. Hosts now live in `hosts/<name>` (vela/vela-dev and iss/iss-dev are separate folders), secrets in the private nix-secrets repo, and CI in `.github/workflows/check.yml`. Use `just deploy <host>` and `just bootstrap <vm|vps|encrypted> <host> <destination>` instead of the raw commands below.

## TODO

- Increase max body size for nginx for wordpress sites. Right now its something like 10mb I think
- backups for arr stack
- navidrome setup
- navidrome backups
- immich backups
- If we want to have multiple machines that export metrics to prometheus, we will need to have urls per machine not just location. Maybe we can just create a subdomain for each machine (top level) or a subdomain on the location. -> `faker.{domain}` or `faker.{location}.{domain}`
- I can probably my public services server on one of my paellas and just set it up in a DMZ
  - Docu sign
  - Jitsi
- Setup automatic upgrades
- Alerts for CPU increases
	- arr stack seems pretty shitly designed. Causes issues. So far bazarr mostly
	- backups for these alerts
- hardware acceleration
	- jellyfin
		- need to look at settings in ui
	- immich
	- navidrome
- Add spotify keys to navidrome for thumbnails for artists
- Setup nvidia to work
	- https://nixos.wiki/wiki/Nvidia
	- https://wiki.nixos.org/wiki/Accelerated_Video_Playback
- shiori backups
- Add monitoring to vela & to iss


```bash
# cleanup aborted switch
sudo systemctl stop nixos-rebuild-switch-to-configuration.service
sudo systemctl reset-failed nixos-rebuild-switch-to-configuration.service
```

## Commands

```bash

# bootstrap vm
# 1. go to vm & run
sudo passwd
# 2. from main machine run
sudo ./scripts/bootstrap-vm.sh -n faker -d root@192.168.122.84

# update vm
sudo -E NIX_SSHOPTS="-i /home/tmx/.ssh/id_ed25519"   nixos-rebuild switch   --target-host root@faker   --flake .#faker

# Update tubby
sudo nixos-rebuild switch --target-host root@tubby --flake .#tubby
sudo -E NIX_SSHOPTS="-i /home/tmx/.ssh/id_ed25519"   nixos-rebuild switch   --target-host root@tubby   --flake .#tubby
# build host
sudo nixos-rebuild switch \
  --flake .#tubby \
  --build-host root@tubby \
  --target-host root@tubby


# Get the local ip of a machine

```

## Torrent block list

- https://gist.github.com/shmup/29566c5268569069c256
- https://github.com/Naunter/BT_BlockLists/

## tailscale tags and users and ACL

- Fuck idk what this is
- But I need to set up a tag so I can make the auth keys stay forever rather than have to renew them every 90D

Can't get https working. I suspect that it is because I don't understand what I need to set up or how it should work. Maybe ask the dude. Maybe read on it

## TODO

- clean up the very ugly code -> I want to make the config's aware of the server. Or have different secrets for each server (which in all fairness might be better)
- Log cleanup. There is a service called log something

## Current Deployworkflow

1. Change vars file for subdomain to use the one related to the machine in question. I should also somehow configure this so I don't have to manually change it every time. But rather it is just set automatically by the machine. I need my own config value.
2. if using syncthing change the sops secrets. Actually I should add the hostname inside the secrets so I don't have to do this
3. run deploy

# Docs

we use config.myConfig for custom configuration created by me.

## Updating an Existing System

```bash
# Update VM
sudo -E NIX_SSHOPTS="-i /home/tmx/.ssh/id_ed25519" \
nixos-rebuild switch --target-host root@192.168.122.8 --flake .#faker

sudo -E NIX_SSHOPTS="-i /home/tmx/.ssh/id_ed25519" \
nixos-rebuild switch --target-host root@faker --flake .#faker # better to use direct ip its shorter
# Update tubby
sudo nixos-rebuild switch --target-host root@tubby --flake .#tubby
# update tubby from host
sudo nixos-rebuild switch --flake .#tubby

# Update Vela
sudo -E NIX_SSHOPTS="-i /home/tmx/.ssh/id_ed25519"   nixos-rebuild switch   --target-host root@vela   --flake .#vela
sudo -E NIX_SSHOPTS="-i /home/tmx/.ssh/id_ed25519" \
  nixos-rebuild switch \
  --target-host root@vela \
  --build-host root@vela \
  --flake .#vela
```

## Bootstrapping a VM

```bash
# bootstrap vm
# 0. Go delete the previous tailscale faker node -> would like for this to not be needed but not sure how
# 1. go to vm & run
sudo passwd
# 2. get the ip
ifconfig
# 3. from main machine run
sudo ./scripts/bootstrap-vm.sh -n faker -d root@<ip>
# For example:
sudo ./scripts/bootstrap-vm.sh -n faker -d root@192.168.122.86
```

## ISS

```bash
# bootstrap command for VM
sudo ./scripts/bootstrap-vm.sh --source-master-key /etc/ssh/iss_ssh_master_key -n iss-dev -d root@<ip>
sudo ./scripts/bootstrap-vm.sh --source-master-key /etc/ssh/iss_ssh_master_key -n iss-dev -d root@<iss-dev-address>

# Update local
sudo -E NIX_SSHOPTS="-i /home/tmx/.ssh/id_ed25519 -p 2525" \
  nixos-rebuild switch \
  --target-host simone@<iss-dev-address> \
  --use-remote-sudo \
  --ask-sudo-password \
  --flake .#iss-dev
sudo -E NIX_SSHOPTS="-i /home/tmx/.ssh/id_ed25519"   nixos-rebuild switch   --target-host root@<iss-dev-address>   --flake .#iss-dev


# boostrap hetzner vm
sudo ./scripts/bootstrap-vps.sh   -n iss   -d root@<iss-address>   -k /home/tmx/.ssh/id_ed25519   --source-master-key /etc/ssh/iss_ssh_master_key   --host-config-dir hosts/iss/iss-prod


# update prod
sudo -E NIX_SSHOPTS="-i /home/tmx/.ssh/id_ed25519 -p 2525" \
  nixos-rebuild switch \
  --target-host simone@<iss-address> \
  --use-remote-sudo \
  --ask-sudo-password \
  --flake .#iss

ssh tmx@<iss-address> -p 2525

```

## Rizos

```bash
# disk encryption ssh to decrypt
ssh -t -i ~/.ssh/id_ed25519 -p 2222 root@{ip}

# 
sudo -E NIX_SSHOPTS="-i /home/tmx/.ssh/id_ed25519" \
  nixos-rebuild switch \
  --target-host root@<rizos-address> \
  --use-remote-sudo \
  --ask-sudo-password \
  --flake .#rizos


```

## Adding a new Host

### Using the master key and same domain

- the url for host services is `{servicename}{config.myConfig.server.location}.{vars.domain}`
- You have to point an A record in cloudflare for each service to the IP address from tailscale.
- if it doesn't show up in tailscale might have to go into the system and run tailscale up

### Using new master key

- Generate new master ssh key
-

## Dependencies / Architecture

- restic does backups to backblaze

## Secrets

- Secrets are handled by sops-nix
- Secrets are stored at `secrets/{hostname}.yaml`
- Secrets are encrypted with a bunch of keys. Don't know which right now

master key is an age encruption used as a universal decryption key for all secrets across all hosts:

1. Key is in .sop.yaml as one that can be used to decrypt
2. Its stored in /etc/ssh/ssh_master_key in the host system
3. It is sent to the VM during deployment using nixos anywhere
4. Its configured in sops.nix as one of the ssh sops can use to decrypt the secrets

We also copy the ssh public master key to the remote host and allow connections with ssh for people that have the private master key. Which we already copied to the remote host.

This is kinda unsafe. Should probably fix at some point for better security

## Backups

- Health checks TODO
- backups are done with restic
- backups are done to backblaze
- backups are in the format of `bucket/{hostname}.{service_name}`

## TODO

- I think it would be nice to add the groups to the main user like this `users.extraGroups.docker.members = [ "username-with-access-to-socket" ];` instead of how I am doing it now with a list and a if they exist check.
- How to manage ports when you have lots of services in the same machine to avoid conflicts?

## Notes wordpress

Potentially need to add this to wp-config.php

```php
if(!empty($_SERVER['HTTP_X_FORWARDED_HOST'])) {

$_SERVER['HTTP_HOST'] = $_SERVER['HTTP_X_FORWARDED_HOST'];

}

if (strpos($_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {

$_SERVER['HTTPS'] = 'on';

$_SERVER['SERVER_PORT'] = 443;

define('FORCE_SSL_ADMIN', true);
}
```


## Remaining questions
- Can I also host a mailserver in the same VM? Should I?
- Can it send emails?
- How can I do the following:
	- Redirect from http to https
	- redirect from www. to https
	- Start with a different domain using http? Or https. Then swap over
- For the tzkransner domain. I actually will need the other ssl generation method. Since its still in wordpress I believe.
- I also need to migrate name servers from hosting.com to cloudflare

Process
1. Migrate DNS to cloudflare -> tzkrasner
2. Nix infect!  -> https://github.com/nix-community/nixos-anywhere/blob/main/docs/quickstart.md
3. I need an IP that is clean for email. 
4. Migrate staging website
3. Either mail server or website first



For migrating websites I can just change my host file to point to the IP of the server that way I can test it


For the passwords I need to use files rather than raw strings. 

### php my admin:

Right now: no.
Current config:
- myConfig.wordpressLiteSpeed in hosts/iss/iss-dev/default.nix does not set bindAddress
- module default is bindAddress = "0.0.0.0" in hosts/iss/modules/wordpress/lightspeed.nix:655
That means phpMyAdmin is bound on all interfaces, not just Tailscale.
So with the current setup:
- 100.x.y.z:8080 over Tailscale should work
- but 192.168.122.112:8080 would also work
- and any other reachable interface/IP would work too, subject to firewall/routing
If you want “available over Tailscale only”, you need one of these:
1. Bind to the Tailscale IP
- set bindAddress = "<tailscale-ip>";
- then phpMyAdmin listens only on that IP
2. Keep 0.0.0.0 and firewall it
- allow 8080/8081 only on tailscale0
- block them on other interfaces
In practice, firewalling is usually the better setup if you want flexibility, but binding to the Tailscale IP is the simplest mental model.
So the direct answer is:
- yes, connecting to the Tailscale IP + port should work
- no, it is not currently restricted to Tailscale only
If you want, I can outline the cleanest way to make phpMyAdmin Tailscale-only in this Nix setup.


### Mailserver

IMAP - SSL/TLS - 993

SMPT - SSL/TLS - 465
Host: mail.<my.domains.main> (see nix-secrets soft secrets)




### TODO SECURITY
- I think we should do the following:
- Have a master key which is sent on first install (with nixos-anywhere). Which can decrypt anything. But is then deleted from the system. An ssh_host key is added which is able to decrypt its related secrets
- We need some way of attaching the host key & public key on activation