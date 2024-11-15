# NOTE: To keep this build up to date, keep the MarkupSafe and mitmproxy defined below up to date.
#
# https://github.com/mitmproxy/mitmproxy/releases
# https://github.com/pallets/markupsafe/releases

# We start from my nginx fork which includes the proxy-connect module from tEngine
# Source is available at https://github.com/rpardini/nginx-proxy-connect-stable-alpine
# This is already multi-arch!
# This is a default value; It can be overridden by passing another value when calling docker.
ARG BASE_IMAGE="docker.io/rpardini/nginx-proxy-connect-stable-alpine:nginx-1.20.1-alpine-3.12.7"
# Could be "-debug"
ARG BASE_IMAGE_SUFFIX="${IMAGE_SUFFIX}"
FROM ${BASE_IMAGE}${BASE_IMAGE_SUFFIX}

# Link image to original repository on GitHub
LABEL org.opencontainers.image.source https://github.com/rpardini/docker-registry-proxy

# apk packages that will be present in the final image both debug and release
RUN apk add --no-cache --update bash ca-certificates-bundle coreutils openssl

# If set to 1, enables building mitmproxy, which helps a lot in debugging, but is super heavy to build.
ARG DO_DEBUG_BUILD="${DEBUG_IMAGE:-"0"}"

# Build mitmproxy via pip. This is heavy, takes minutes do build and creates a 90mb+ layer.
# NOTES:
#   * cache mounts are used foor improved repeated build times. These caches are not included in the
#     final image and as such need and should not be purged.
#   * rust is installed using rustup to get the latest version, as the alpine package was too old for this build
RUN \
 --mount=type=cache,mode=0755,target=/var/cache/apk \
 --mount=type=cache,mode=0755,target=/root/.cache/pip \
 --mount=type=cache,mode=0755,target=/root/.cargo \
 --mount=type=cache,mode=0755,target=/root/.rustup \
 [[ "a$DO_DEBUG_BUILD" == "a1" ]] && { echo "Debug build ENABLED." \
 && apk add --update --cache-max-age 120 su-exec libffi libstdc++ python3 py3-six py3-idna py3-certifi py3-setuptools curl \
 && apk add --update --cache-max-age 120 --virtual build-deps git g++ libffi-dev openssl-dev python3-dev py3-pip py3-wheel bsd-compat-headers \
 && apk add rustup \
 && rustup-init -yq \
 && source "$HOME/.cargo/env" \
 && mkdir /venv \
 && cd venv \
 && python -m venv . \
 && source bin/activate \
 && MAKEFLAGS="-j$(nproc)" LDFLAGS=-L/lib pip install MarkupSafe==2.1.5 mitmproxy==10.4.2 \
 && apk del --purge build-deps \
 ; } || { echo "Debug build disabled." ; }

# Required for mitmproxy
ENV LANG=en_US.UTF-8

# Create the cache directory and CA directory
RUN mkdir -p /docker_mirror_cache /ca

# Expose it as a volume, so cache can be kept external to the Docker image
VOLUME /docker_mirror_cache

# Expose /ca as a volume. Users are supposed to volume mount this, as to preserve it across restarts.
# Actually, its required; if not, then docker clients will reject the CA certificate when the proxy is run the second time
VOLUME /ca

# Add our configuration
ADD nginx.conf /etc/nginx/nginx.conf
ADD nginx.manifest.common.conf /etc/nginx/nginx.manifest.common.conf
ADD nginx.manifest.stale.conf /etc/nginx/nginx.manifest.stale.conf

# Add our very hackish entrypoint and ca-building scripts, make them executable
ADD entrypoint.sh /entrypoint.sh
ADD create_ca_cert.sh /create_ca_cert.sh
RUN chmod +x /create_ca_cert.sh /entrypoint.sh

# Add Liveliness Probe script for CoreWeave. NOTE: Depends on curl being installed.
ADD liveliness.sh /liveliness.sh
RUN chmod +x /liveliness.sh

# Clients should only use 3128, not anything else.
EXPOSE 3128

# In debug mode, 8081 exposes the mitmweb interface (for incoming requests from Docker clients)
EXPOSE 8081
# In debug-hub mode, 8082 exposes the mitmweb interface (for outgoing requests to DockerHub)
EXPOSE 8082

## Default envs.
# A space delimited list of registries we should proxy and cache; this is in addition to the central DockerHub.
ENV REGISTRIES="k8s.gcr.io gcr.io quay.io"
# A space delimited list of registry:user:password to inject authentication for
ENV AUTH_REGISTRIES="some.authenticated.registry:oneuser:onepassword another.registry:user:password"
# Should we verify upstream's certificates? Default to true.
ENV VERIFY_SSL="true"
# Enable debugging mode; this inserts mitmproxy/mitmweb between the CONNECT proxy and the caching layer
ENV DEBUG="false"
# Enable debugging mode; this inserts mitmproxy/mitmweb between the caching layer and DockerHub's registry
ENV DEBUG_HUB="false"
# Enable nginx debugging mode; this uses nginx-debug binary and enabled debug logging, which is VERY verbose so separate setting
ENV DEBUG_NGINX="false"

# Manifest caching tiers. Disabled by default, to mimick 0.4/0.5 behaviour.
# Setting it to true enables the processing of the ENVs below.
# Once enabled, it is valid for all registries, not only DockerHub.
# The envs *_REGEX represent a regex fragment, check entrypoint.sh to understand how they're used (nginx ~ location, PCRE syntax).
ENV ENABLE_MANIFEST_CACHE="false"

# 'Primary' tier defaults to 10m cache for frequently used/abused tags.
# - People publishing to production via :latest (argh) will want to include that in the regex
# - Heavy pullers who are being ratelimited but don't mind getting outdated manifests should (also) increase the cache time here
ENV MANIFEST_CACHE_PRIMARY_REGEX="(stable|nightly|production|test)"
ENV MANIFEST_CACHE_PRIMARY_TIME="10m"

# 'Secondary' tier defaults any tag that has 3 digits or dots, in the hopes of matching most explicitly-versioned tags.
# It caches for 60d, which is also the cache time for the large binary blobs to which the manifests refer.
# That makes them effectively immutable. Make sure you're not affected; tighten this regex or widen the primary tier.
ENV MANIFEST_CACHE_SECONDARY_REGEX="(.*)(\d|\.)+(.*)(\d|\.)+(.*)(\d|\.)+"
ENV MANIFEST_CACHE_SECONDARY_TIME="60d"

# The default cache duration for manifests that don't match either the primary or secondary tiers above.
# In the default config, :latest and other frequently-used tags will get this value.
ENV MANIFEST_CACHE_DEFAULT_TIME="1h"

# Should we allow actions different than pull, default to false.
ENV ALLOW_PUSH="false"

# If push is allowed, buffering requests can cause issues on slow upstreams.
# If you have trouble pushing, set this to false first, then fix remainig timouts.
# Default is true to not change default behavior.
ENV PROXY_REQUEST_BUFFERING="true"

# Stream data; reduce TTFB
# Effectively disables caching
# Default is true to not change default behavior.
ENV PROXY_BUFFERING="true"

# Should we allow overridding with own authentication, default to false.
ENV ALLOW_OWN_AUTH="false"

# Should we allow push only with own authentication, default to false.
ENV ALLOW_PUSH_WITH_OWN_AUTH="false"


# Timeouts
# ngx_http_core_module
ENV SEND_TIMEOUT="60s"
ENV CLIENT_BODY_TIMEOUT="60s"
ENV CLIENT_HEADER_TIMEOUT="60s"
ENV KEEPALIVE_TIMEOUT="300s"
# ngx_http_proxy_module
ENV PROXY_READ_TIMEOUT="60s"
ENV PROXY_CONNECT_TIMEOUT="60s"
ENV PROXY_SEND_TIMEOUT="60s"
# ngx_http_proxy_connect_module - external module
ENV PROXY_CONNECT_READ_TIMEOUT="60s"
ENV PROXY_CONNECT_CONNECT_TIMEOUT="60s"
ENV PROXY_CONNECT_SEND_TIMEOUT="60s"

# Did you want a shell? Sorry, the entrypoint never returns, because it runs nginx itself. Use 'docker exec' if you need to mess around internally.
ENTRYPOINT ["/entrypoint.sh"]
