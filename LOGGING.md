# Logging using log aggregation

There are two ways that I am playing with to perform logging to an
external logging service: Google Cloud stackdriver logging and Grafana
Cloud Loki. I do like to check all my logs at a central location for all
my various linux servers. Logging at one central location also has the
advantage that I can centrally manage any alerting based on strings in
the logs as well as being sure that it is not that easy to tamper with
log files in case of intruders. Both Google Cloud and Grafana Cloud do
have generous free quotas to use their services, and I am using both in
different projects. I started with Google Cloud many years back, so I
may be a bit more familar there.

There are two parts for capturing the logs of individual machines, one
is redirecting the journald logs to the cloud logging service, this is
done by natively installing [fluent-bit](https://www.fluentbit.io) on
your machine. There are two ways to configure fluent-bit, I will use
the yaml based config file here. To make that happen I use the following
as /etc/systemd/system/fluent-bit.service.d/override.conf for the
fluent-bit daemon:

```
[Service]
ExecStart=
ExecStart=/usr/bin/fluent-bit -c /etc/fluent-bit/fluent-bit.yaml
```

The second part is instructing docker to send the collected stdout and
stderr of the managed containers to the same cloud logging provider.
There are docker plug-ins available for both Google Cloud and Grafana
Cloud to perform this task. Both work best if the docker apps are
configured to emit just plain json lines for their logging.

But I am surprised how many developers spend lost time (in my opinion)
to build homegrown logging into their apps that include log file rotation
and colorizing their output with ANSI escape sequences.

## Logging to Google Cloud Logging (Stackdriver)

To be able to log to Google Cloud, you will need to create a service
account that should include the following roles:

* Logs Writer
* Error Reporting Writer

Save the service account key as a json file, it is used both by fluent-bit and docker below.

### fluent-bit for sending the journal

A typical fluent-bit.yaml config for logging to Google Cloud looks like
this:

```
service:
  flush: 1
  daemon: Off
  log_level: info
  http_server: Off
  http_listen: 0.0.0.0
  http_port: 2020
  storage.metrics: on

pipeline:
  inputs:
    - name: systemd
      tag: host.systemd
      DB: /var/lib/fluent-bit/journal.db
      Lowercase: on
      Strip_Underscores: on
      processors:
        logs:
          - name: lua
            call: modify
            code: |
              function modify(tag, timestamp, record)
                new_record = record
                prio = record["priority"]
                if(prio == "7")
                then
                  new_record["severity"] = "DEBUG"
                elseif(prio == "6")
                then
                  new_record["severity"] = "INFO"
                elseif(prio == "5")
                then
                  new_record["severity"] = "NOTICE"
                elseif(prio == "4")
                then
                  new_record["severity"] = "WARNING"
                elseif(prio == "3")
                then
                  new_record["severity"] = "ERROR"
                elseif(prio == "2")
                then
                  new_record["severity"] = "CRITICAL"
                elseif(prio == "1")
                then
                  new_record["severity"] = "ALERT"
                elseif(prio == "0")
                then
                  new_record["severity"] = "EMERGENCY"
                end
                return 1, timestamp, new_record
              end
  outputs:
    - name: stackdriver
      match: '*'
      severity_key: severity
      google_service_credentials: /etc/fluent-bit/my-service-acct.json
      resource: gce_instance
      resource_labels: instance_id=myhost,zone=myzone
```

The biggest part in the above config is mapping journald priorities to
stackdriver severities. Please note the use of the Google Cloud
credentials file and the addition of standard instance_id and zone
resource labels. The directory /var/lib/fluent-bit for journald
synchronization needs to be created once.

### Docker log plug-in

I used to use the gcplogs log driver built into docker, but I am really
switching all my projects to structured json based logging and was
looking for ways to directly feed that into google cloud logging. The
docker gpclogs driver does not do this (it forwards the JSON as one big
log line), but I found the excellent project
[ngcplogs](https://github.com/nanoandrew4/ngcplogs)
that modified the gcplogs driver to extract the structured log info.

This driver is a docker plugin and is installed like this (for an ARM
based host):

````
docker plugin install nanoandrew4/ngcplogs:linux-arm64-v1.3.0 --alias ngcplogs --grant-all-permissions
````

The driver is configured as usual in /etc/docker/daemon.json
like this:

```
{
	"log-driver": "ngcplogs",
	"log-opts": {
		"exclude-timestamp" : "true",
		"extract-gcp" : "true",
		"extract-caddy" : "true",
		"gcp-project": "hosting-XXXXXX",
		"gcp-meta-name": "myhost",
        "gcp-meta-zone": "myzone",
		"credentials-json" : "your_json_escaped_credentials.json_file_content"
	}
}
```

The escaped json string for the Google service account with log writing
permissions can be generated with the json-escape.go program like this:

```
./json-escape.sh </path/to/my-service-acct.json
```

The extract-gcp option extracts already existing Google Cloud style
Trace, labels and source line information from applications that already
expect their output to be scanned by Google Cloud Logging. For Golang
apps that use logrus
[stackdriver-gae-logrus-plugin](https://github.com/andyfusniak/stackdriver-gae-logrus-plugin)
or for log/slog based ones [slogdriver](https://github.com/jussi-kalliokoski/slogdriver) this works nicely.

The slogdriver adapter for log/slog does not parse the traceparent HTTP
header, I have thus created small piece of middleware that I use to
inject the trace information as expected by slogdriver into the request
context: [traceparent](https://github.com/jum/traceparent).

The extract-caddy option extracts fields from Caddy logs to be able to
use caddy as a proper trace parent and also make Google Cloud console
display caddy access log entries as HTTP requests. To make sure that
caddy emits trace parent information the tracing directive in the
Caddfile is used. But tracing involves the complete OTEL machinery,
so this build of caddy includes the simpletrace caddy module to just
do traceparent handling. For stackdriver format logging the global
section of the Caddfile should have:

```
order simpletrace first
```

The default snippet that is included should look like this:

```
simpletrace {
  format stackdriver
}
```

More information can be found in the simpletrace github repo
[caddy-simpletrace](https://github.com/jum/caddy-simpletrace)

The neat effect of all this that I get a fully distributed tracing across
multiple nodes without going through the hoops of setting up a full blown
OTEL setup and a really nice log viewer in the Google Cloud Console.

### Alert Notifications

Google cloud logging does have some powerful alerting, for example based
on logs. I do use alerting to be notified stack traces and I also use some
log message based alerting. I have a simple project:
[alert2discord](https://gitea.mager.org/jum/alert2discord) that forwards
Google Cloud Alerts to a discord channel using a webhook running as Cloud
Run app.

## Logging to Grafana Cloud (Loki)

For logging to Grafana Loki you will need to get the credentials from
the Loki section in the Grafana Cloud account. This includes the host to
send logs to, the user id and password.

### fluent-bit for sending the journal

A typical fluent-bit.yaml config for logging to Grafana Loki looks like
this:

```
service:
  flush: 1
  daemon: Off
  log_level: info
  http_server: Off
  http_listen: 0.0.0.0
  http_port: 2020
  storage.metrics: on

pipeline:
  inputs:
    - name: systemd
      tag: host.systemd
      DB: /var/lib/fluent-bit/journal.db
      Lowercase: on
      Strip_Underscores: on
      processors:
        logs:
          - name: lua
            call: modify
            code: |
              function modify(tag, timestamp, record)
                new_record = record
                prio = record["priority"]
                if(prio == "7")
                then
                  new_record["level"] = "DEBUG"
                elseif(prio == "6")
                then
                  new_record["level"] = "INFO"
                elseif(prio == "5")
                then
                  new_record["level"] = "NOTICE"
                elseif(prio == "4")
                then
                  new_record["level"] = "WARN"
                elseif(prio == "3")
                then
                  new_record["level"] = "ERROR"
                elseif(prio == "2")
                then
                  new_record["level"] = "CRITICAL"
                elseif(prio == "1")
                then
                  new_record["level"] = "ALERT"
                elseif(prio == "0")
                then
                  new_record["level"] = "EMERGENCY"
                end
                return 1, timestamp, new_record
              end
  outputs:
    - name: loki
      match: '*'
      labels: job=journal, instance=myhost, zone=myzone, level=$level, $systemd_unit, tag=$TAG
      host: logs-prod-XXX.grafana.net
      port: 443
      tls: on
      tls.verify: on
      line_format: json
      http_user: my_grafana_user_id
      http_passwd: my_grafana_password
```

The biggest part in the above config is mapping journald priorities to
Loki log levels. There is a subtle difference between stackdriver and
Loki here, the WARNING lable is only understood if written as WARN by
Loki. Please note the use of the Grafana Cloud Loki credentials and the
addition of standard instance_id and zone resource labels. The
directory /var/lib/fluent-bit for journald synchronization needs to be
created once.

### Docker log plug-in

To install the Loki docker plugin is installed like this (for an ARM
based host):

```
docker plugin install grafana/loki-docker-driver:3.5.0-arm64 --alias loki --grant-all-permissions
```

The driver is configured as usual in /etc/docker/daemon.json
like this:

```
{
	"log-driver": "loki",
	"log-opts": {
		"loki-url": "https://my_grafana_user_id:my_grafana_password@logs-prod-XXX.grafana.net/loki/api/v1/push",
		"loki-external-labels": "job=docker,instance=myhost,zone=myzone"
	}
}
```

The loki docker plug-in does already handle log lines in json format. To
propagate traceparent information for golang apps using a suitable http
middleware and adding trace information to the log see:
[slog-traceparent](https://github.com/jum/slog-traceparent)

The simpletrace format for Loki would be "tempo".
