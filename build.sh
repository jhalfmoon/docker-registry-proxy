#!/bin/bash -eux
#
# This script is mainly meant to help develop / debug this image build

# These variables must match those used to build the base image.
# See https://github.com/jhalfmoon/nginx-proxy-connect-stable-alpine
ALPINE_VER=3.20
NGINX_VER=1.26.0
DOCKER_PROXY_DEBUG=1

if [[ DOCKER_PROXY_DEBUG -eq 1 ]] ; then
    IMAGE_SUFFIX='-debug'
else
    IMAGE_SUFFIX=''
fi

# This image should be built earlier. If that is not the case, this build will fail.
BASE_IMAGE_NAME="nginx-proxy-connect-stable-alpine:nginx-${NGINX_VER}-alpine-${ALPINE_VER}${IMAGE_SUFFIX}"
PROXY_IMAGE_NAME=docker-registry-proxy${IMAGE_SUFFIX}:newbuild

docker build \
    --progress=plain \
    --build-arg BASE_IMAGE=$BASE_IMAGE_NAME \
    --build-arg DO_DEBUG_BUILD=$DOCKER_PROXY_DEBUG \
    -t $PROXY_IMAGE_NAME .
