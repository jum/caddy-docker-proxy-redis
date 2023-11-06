# syntax = docker/dockerfile:1-experimental
# Dockerfile for building the project with static assets
FROM golang:1.21-bullseye as build

WORKDIR /goapp

RUN --mount=type=cache,target=/root/.cache/go-build  GOOS=${TARGETOS} \
	GOARCH=${TARGETARCH} \
	go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

RUN --mount=type=cache,target=/root/.cache/go-build  GOOS=${TARGETOS} \
	GOARCH=${TARGETARCH} \
	xcaddy build \
		--with github.com/gamalan/caddy-tlsredis \
		--with github.com/lucaslorentz/caddy-docker-proxy/v2

# Now copy it into our base image.
FROM alpine:latest as alpine
EXPOSE 80 443 443/udp 2019
ENV XDG_CONFIG_HOME /config
ENV XDG_DATA_HOME /data
RUN apk add -U --no-cache ca-certificates curl
COPY --from=build /goapp/caddy /bin/caddy
ENTRYPOINT ["/bin/caddy"]
CMD ["docker-proxy"]
