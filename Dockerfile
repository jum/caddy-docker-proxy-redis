# Dockerfile for building the project with static assets
FROM --platform=$BUILDPLATFORM golang:1.22-bullseye as build

WORKDIR /goapp
ARG TARGETOS TARGETARCH
ENV CGO_ENABLED=0

RUN --mount=type=cache,target=/root/.cache/go-build \
	--mount=type=cache,target=/go/pkg \
	go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

RUN --mount=type=cache,target=/root/.cache/go-build \
	--mount=type=cache,target=/go/pkg \
	GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
	xcaddy build \
		--with github.com/pberkel/caddy-storage-redis \
		--with github.com/caddy-dns/cloudflare \
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
