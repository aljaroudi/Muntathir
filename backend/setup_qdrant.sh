#!/bin/sh
set -eu
# The existing volume can be reused during cutover, but never by two running containers.
container_name=${QDRANT_CONTAINER:-muntathir-search-qdrant}
volume_name=${QDRANT_VOLUME:-muntathir-search-qdrant}
container system start
if ! container volume inspect "$volume_name" >/dev/null 2>&1; then
  container volume create "$volume_name"
fi
if container inspect "$container_name" >/dev/null 2>&1; then
  container start "$container_name"
else
  container run -d --name "$container_name" --cpus 4 --memory 8G \
    -p 127.0.0.1:56333:6333 -v "$volume_name:/qdrant/storage" \
    -e QDRANT__TELEMETRY_DISABLED=true \
    docker.io/qdrant/qdrant:v1.20.0
fi
