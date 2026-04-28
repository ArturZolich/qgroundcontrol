#!/usr/bin/env bash
set -euo pipefail

mkdir -p $(pwd)/buildUbuntu

docker run \
    -it --name qgcUbuntu77 \
    --cap-add SYS_ADMIN --device /dev/fuse --security-opt apparmor:unconfined \
    -v "$(pwd):/project/source" \
    -v "$(pwd)/buildUbuntu:/project/build" \
    qgc-ubuntu-docker -l
