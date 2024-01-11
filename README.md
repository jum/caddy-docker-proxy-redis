# caddy-docker-proxy-redis

## How I do run my linux servers

I do have a few linux virtual servers spread around in various data
centers. Originally that was mostly nginx front ends to various locally
installed applications, all supervised by systemd. Changing to caddy
as the proxy server was a fresh breeze as the configuration got much
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
[Unit]
After=tailscaled.service

[Service]
Environment="GOOGLE_APPLICATION_CREDENTIALS=/home/adminuser/.serviceaccts/hosting-XXXXXX-XXXXXXXXXXXX.json"
```

The After= section makes sure that docker starts after tailscale is
initialized. This is necessary to achieve name resolution via the
tailscale magic DNS feature from within the docker caddy container. If
you cannot resolve your services in your tailnet (this example uses a
redis server reachable from all nodes over the private tailnet), you can
check the resolv.conf file in the caddy container:

```
docker exec -it caddy cat /etc/resolv.conf
```

On some Linux distributions the /etc/resolv.conf is overwritten multiple
times, in these cases the caddy docker container picked up an
intermidiate version of resolv.conf and not the final one. So the caddy
resolv.conf should match the hosts /etc/resolv.conf exactly.

From my experience the use of NetworkManager together with cloud-init is
prone to produce these situation. In these cases it might be advised to
change the above dependency to After=tailscale-up.service and use the
following tailscale-up.service file:

```
[Unit]
Description=Wait for tailscale up
After=tailscaled.service

[Service]
Type=oneshot
ExecStart=/usr/bin/sh -c "/usr/bin/tailscale up; echo tailscale-up"
```

Experimenting with systemd-resolved might also reduce the number of
overwrites to the resolv.conf file.

GOOGLE_APPLICATION_CREDENTIALS injects the credentials of
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
docker-proxy, tls-redis and caddy-dns/cloudflare plugins. I do build both
AMD64 and ARM64 versions of each of my containers as my linux systems
use both of these architectures.

The caddy subdirectory showcases a typical caddy configuration. I do run
caddy in its container with ports forwarded for port 80 and 443 TCP and
443 UDP for QUIC aka HTTP/3. For easier configuration of the individual
services I do include Caddyfile snippets in the config/Caddfile
subdirectory. The caddy docker-proxy configuration to build a final
Caddyfile can get a bit obscure for more complicated containers like
nextcloud. I use a defaulthdr snippet (for an example see the whoami
section later) to set HSTS headers, set the log file and enable
compression. This snipped might be replaced by the norobots snippet that
whould inhibit crawling for API style sites or the robots snippet for
normal content with some obnoxius robots excluded.

This Caddyfile also defines a https site on the tailscale side for the
host, this has by default just a /health endpoint for health checking.
The watchtower and adminer containers do add subdirectory endpoints here
for the watchtower API and for examining database content.

The volume /run/containers for caddy might look unfamilar, but I use
this to expose my own services via unix domain sockets. If you do not
expect to proxy to upstream servers via unix domain sockets you might
omit that volume.

The volume /var/www/html is for interoperability with php fastcgi in the
nextcloud example, if you do not need nextcloud drop this.

To support naked domains (e.g. redirecting from example.com to
www.example.com) I use the naked snippet. You need to define an A (and
AAAA, if you use IPv6) record pointing to your host instance besides the
normal CNAME record pointing to the canonical name for your host for the
www subdomain. This would normally look like this:

```
; SOA Record
@	3600	 IN 	SOA	ns.example.com.	jum.example.com. (
					2023081200
					28800
					7200
					604800
					3600
					) 

; A Record
@	3600	 IN 	A	X.X.X.X

; AAAA Record
@	600	 IN 	AAAA	XXXX:XXX:XXXX:XXX::1

; CNAME Record
www	3600	 IN 	CNAME	www.example.org.

```

A container serving the www.example.com domain would have this in its
label section in the docker-compose.yml:

```
    labels:
      caddy_0: example.com
      caddy_0.import: naked
	  caddy_0.tls.dns: cloudflare {env.CF_API_KEY}
      caddy_1: www.example.com
	  caddy_1.tls.dns: cloudflare {env.CF_API_KEY}
      caddy_1.import: robots
      caddy_1.skip_log: /health
      caddy_1.reverse_proxy: "unix//run/containers/example-www.sock"
```

This assumes that container serving the example.com domain is listening
under a UNIX domain socket and also exposes a /health endpoint that
should not be recorded in the logs.

Recently I started to use ACME DNS verification for some domains, for
this reason I add the cloudflare caddy DNS module for my DNS provider. The
above configuration with caddy_X.tls.dns tell caddy to use ACME DNS
instead of HTTP based verification for generating TLS certificates. You
could also add this to the base Caddyfile snippet, but only if you use
only one DNS provider account. I recently moved from godaddy to
cloudflare for hosting my DNS, and although I initially purchased my
domains using multiple godaddy accounts I can now update all my domains
using a single CF_API_KEY for cloudflare. I have thus moved this into
the main Caddyfile under the acme_dns global configuration.

### Surviving a tailscaled restart

The docker container mounts the runtime directory of tailscale and not
the socket file itself (how it is done for the docker socket). This is
due to the fact that docker virtual mounts will not notice if the
underlying file is recreated upon restarting the listening daemon. For
the docker socket this does not matter, as if docker is restart all
containers will restart as well. As a further complication, the
tailscaled.service files not specify the option to preserve the
directory /var/run/tailscale at daemon restart, making a mount of
/var/run/tailscale instead of the socket not work. But there is an
option in systemd to make that work, create a directory named
/etc/systemd/system/tailscaled.service.d and create a file named
runtimedir.conf with the following contents:

```
[Service]
RuntimeDirectoryPreserve=yes
```

This will prevent systemd from removing the /var/run/tailscale directory
and the caddy container will pick the changed tailscaled socket on the
next access.

I have submitted a feature request to tailscale to make that the
default. You might want to chime in here to make it happen:

https://github.com/tailscale/tailscale/issues/9362

## Watchtower

The container defined in the watchtower subdirectory is responsible for
updating the containers actually running on the host, with the exception
of watchtower itself. Letting watchtower update itself does not appear
to be working, but fortunately this is mature software and changes seldomly.
Please note that you should set a random password for the watchtower API
in this docker-compose.yml. This container also needs to access your
docker credentials in your home directory for accessing your docker
repositories. A script like this can be used to trigger a scan for
updated containers for an individual host:

```
#!/bin/sh
curl -s -H "Authorization: Bearer Secret_Token" \
	https://host.tailXXXXX.ts.net/watchtower/v1/update
```

I do use this in my CI/CD pipelines to trigger container reloads
on affected hosts after building a container.

## Whoami

For debugging (and as a placeholder to aquire certificates) I tend to
start an instance of whoami on the canonical host name of the linux box.
For hosts that may be running postfix and dovecot or other services
outside the caddy/docker universe a seperate project in
[certwatch](https://github.com/jum/certwatch) can be used to monitor a
set of certificates in the caddy redis storage and write the
certificates to /var/lib/certwatch and restart systemd services.

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
you would need to change the IP number 100.X.X:X to be able to access
these databases from anywhere inside your tailnet.

## Gitea

I do host my own private git repositories and the assorted CI/CD
pipelines using gitea. The subdirectiory gitea shows an example
docker-compose.yml file. Please note that I use something like this in
my app.ini for gitea to reverse proxy via a unix socket:

```
[server]
SSH_DOMAIN = gitea.example.org
DOMAIN = gitea.example.org
PROTOCOL = http+unix
HTTP_PORT = 3000
HTTP_ADDR = /run/containers/gitea.sock
```

## Nextcloud

The Nextcloud configuration in the Caddfile is rather lengthy, so I
decided to put that as a snippet in the base Caddyfile and just put the
import in the nextcloud/docker-compose.yml. The php fastcgi
configuration relies on the .php files to be present under the same path
in both the caddy and the nextcloud containers, note the according volume
mounts of /var/www/html in both containers.

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

docker compose ls --format json|jq -r '.[]|.ConfigFiles' | while read yaml
do
	dir=`dirname "$yaml"`
	if test -x "$dir/dumpdb.sh"
	then
		sudo -u adminuser sh -c "cd $dir; ./dumpdb.sh"
	fi
done

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

If the directory with the docker-compose.yaml file has a dumpdb.sh
script, it is called to dump any databases before backing up. The script
for redis will dump the memory to a file, the mariadb and postgres
containers will dump the complete database. I also use this with some
sqlite projects to perform a textual dump of the database.
