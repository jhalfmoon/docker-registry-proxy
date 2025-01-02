#!/bin/bash -eux
#
# This script is mainly meant to help develop / debug this image build.

HERE=$(dirname $(readlink -f $0))
BASE_IMAGE_URL=https://github.com/jhalfmoon/nginx-proxy-connect-stable-alpine
BASE_IMAGE_DIR=../nginx-proxy-connect-stable-alpine
if [[ ! -d $BASE_IMAGE_DIR ]] ; then
    echo "ERROR: $BASE_IMAGE_DIR does not exist. Suggested action:"
    echo "git clone $BASE_IMAGE_URL $HERE/$BASE_IMAGE_DIR"
    exit 1
fi

# The following variables must match those used to build the base image.
ALPINE_VER=$(cat $BASE_IMAGE_DIR/Dockerfile | grep 'FROM alpine:' | cut -d: -f2)
NGINX_VER=$(cat $BASE_IMAGE_DIR/Dockerfile | grep 'ENV NGINX_VERSION' | tr '=' ' ' | awk '{print $3}')

DOCKER_PROXY_DEBUG=1

if [[ DOCKER_PROXY_DEBUG -eq 1 ]] ; then
    IMAGE_SUFFIX='-debug'
else
    IMAGE_SUFFIX=''
fi

BASE_IMAGE_NAME="nginx-proxy-connect-stable-alpine:nginx-${NGINX_VER}-alpine-${ALPINE_VER}${IMAGE_SUFFIX}"
PROXY_IMAGE_NAME=docker-registry-proxy${IMAGE_SUFFIX}:newbuild

cd $BASE_IMAGE_DIR
./build.sh
cd -

# The base image must be available as it was buit in the previous step.
if ! (docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "$BASE_IMAGE_NAME" &> /dev/null) ; then
    echo "ERROR: Base image $BASE_IMAGE_NAME is not available. Exiting."
    exit 1
fi

# You might want to cleanup now and then. Caches can eat up much storage.
# This is also useful for debugging and testing build times.
#
# docker builder prune --all --force

time docker build \
    --progress=plain \
    --build-arg BASE_IMAGE=$BASE_IMAGE_NAME \
    --build-arg DO_DEBUG_BUILD=$DOCKER_PROXY_DEBUG \
    -t $PROXY_IMAGE_NAME \
    .

docker images
