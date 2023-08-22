# caddy-docker-proxy-redis

## How I do run my linux servers

I do have a few linux virtual servers spread around in various data
centers. Originally that was mostly nginx front ends to various locally
installed applications, all supervised by systemd. Changing to caddy
as the proxy server was a fresh breaze as the configuration got much
simpler and there where no shell scripts needed any longer to update
certificates with letsencrypt. Still a lot installed on each server, but
simpler.

My most recent iteration in making the administrative side easier is the
following setup:

* All nodes run tailscale as an overlay VPN for admin functions.
* All nodes run docker and one instance of the watchtower container
    for easy automatic upgrades of the individual packages.
* Docker is configured to log to Google Cloud Logging for easy log file
    monitoring. This is may not be relevant for most people, but for me
    it makes perusing logs much easier.
* All docker containers are started via a docker-compose.yml file. Each
    of those gets their own subdirectory with the docker-compose.yml
    file alongside any additional configuration and data volumes needed.
* I run caddy with the docker-proxy and caddy-tls-redis plugins in a
    container as front end proxy.
* Individual containers for the services use caddy docker proxy label
    fragments for configuration in the individual docker-compose.yml
    files.
* All caddy instances share a common storage backend (a redis instance
    reached via the tailscale overlay vpn) for tls certificate storage.
    This facilitates easy moving a service from one server box to another
    without a lot of downtime due to missing TLS certificates.
* I use an instance of gatus to monitor all these services and get
    notified by email about any failures. The caddy health check is on
    the tailscale side, so I check both the status of the tailnet as
    well as caddy basics working in one check.

All the referenced docker-compose files below assume a docker bridge
network named caddy, see the networks.sh script.

I do override configuration on the docker service via creating the
directory /etc/systemd/system/docker.service.d and creating a file
override.conf like this:

```
[Service]
After=tailscaled.service
Environment="GOOGLE_APPLICATION_CREDENTIALS=/home/amdinuser/.serviceaccts/hosting-XXXXXX-XXXXXXXXXXXX.json"
```

The After= section makes sure that docker starts after tailscale is
innitialized. GOOGLE_APPLICATION_CREDENTIALS injects the credentials of
a service account that has log and error reporting permissions on a
Google Cloud project. I modify the docker daemon config in
/etc/docker/dameon.json like this:

```
{
	"log-driver": "gcplogs",
	"log-opts": {
		"gcp-project": "hosting-XXXXXX",
		"gcp-meta-name": "myservername"
	}
}
```

The Google Cloud configuration is optional if you like to use journalctl
on the individual hosts.

## Caddy

The root directory of this repo contains the Dockerfile and a
build-docker.sh script to build the container that runs caddy with the
docker proxy and tls-redis plugins. I do build both AMD64 and ARM64
versions of each of my containers as my linux systems use both of these
architectures. The caddy subdirectory showcases a typical caddy
configuration. I do run caddy in its container with ports forwared for
port 80 and 443 TCP and 443 UDP for QUIC aka HTTP/3. For easier
configuration of the individual services I do include Caddyfile snippets
in the config/Caddfile subdirectory. The caddy docker-proxy
configuration to build a final Caddyfile can get a bit obscure for more
complicated containers like nextcloud.

This Caddyfile also defines a https site on the tailscale side for the
host, this has by default just a /health endpoint for health checking.
The watchtower and adminer containers do add subdirectory endpoints here
for the watchtower API and for examining database content.

The volume /run/containers for caddy might look unfamilar, but I use
this to expose my own services via unix domain sockets. If you do not
expect to proxy to upstream servers via unix domain sockets you might
omit that volume.

## Watchtower

The container defined in the watchtower subdirectory is responsible for
updating the containers actually running on the host, with the exception
of watchtower itself. Lettings watchtower update itself does not appear
to be working, but fortunately this is mature and changes seldomly.
Please note that you should set a random password for the watchtower API
in this docker-compose.yml. This container also needs to access your
docker credentials in your home directory for accessing your docker
repositories.

## Whoami

For debugging (and as a placeholder to aquire certificates) I tend to
start an instance of whoami on the canonical host name of the linux box.
For hosts that may be running postfix and dovecot or other services
outside the caddy/docker universe a seperate project in
github.com/jum/certwatch can be used to monitor a set of certificates in
the caddy redis storage and write the certificates to /var/lib/certwatch
and restart systemd services.

## Adminer

Adminer is a nice tool to examine mariadb or postgres databases. I do
only run it exposed on the tailscale host name under the /adminer
endpoint, and then only when I need it.

## Redis

One node in the tailscale VPN should run redis for storing the TLS
certifcates. The redis subdirectory contains an example for this, please
note that this also has to expose the tailnet side of the hosts IP (the
100.X.X.X IP in the docker-compose.yml file for use in redis URLs.

## Databases

The postgres and mariadb subdorectories contain docker-compose files to
start any of these databases. I have used mariadb in the past but on new
projects I am mostly using postgres. Please note that for both databases
you would need to change the IP numer 100.X.X:X to be able to access
these databases from anywhere inside you tailnet.

## Backup

I do run nightly backups via restic to a Hetzner storage box via SFTP.
After configuring one of those and putting these credentials into your
.ssh/config and into /root/.ssh/config as well I run using a script like
this:

```
#!/bin/sh
export PATH=$PATH:/usr/local/bin

if test -t 0
then
	VERBOSE=
else
	VERBOSE=-q
fi
export RESTIC_REPOSITORY=sftp:storage:backup-hostXXX/restic
export RESTIC_PASSWORD_FILE=$HOME/.restic-backup-hostXXX

sudo -u adminuser sh -c "cd ~/web/redis; ./dumpdb.sh"
sudo -u adminuser sh -c "cd ~/web/mariadb; ./dumpdb.sh"
sudo -u adminuser sh -c "cd ~/web/postgres; ./dumpdb.sh"

restic $VERBOSE backup --exclude-caches=true \
	/etc/docker /var/lib/docker \
	/usr/local \
	/home/adminuser /root
restic $VERBOSE forget \
	--keep-daily 7 --keep-weekly 5 --keep-monthly 12 \
	--keep-yearly 100 --prune

chown -R adminuser:adminuser /home/adminuser/.cache/restic
```

This scripts assumes that the subdirectories for the docker containers
are kept under ~adminuser/web and that the adminuser is a member of the
docker group.
