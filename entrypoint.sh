#!/busybox/sh
set -e pipefail

export REGISTRY=${INPUT_REGISTRY:-"docker.io"}
export IMAGE=${INPUT_IMAGE:-$GITHUB_REPOSITORY}
export TAG=${INPUT_TAG:-$([ "$GITHUB_REF" == "master" ] && echo latest || echo $GITHUB_REF)}
export TAG=${TAG:-"latest"}
export USERNAME=${INPUT_USERNAME:-$GITHUB_ACTOR}
export PASSWORD=${INPUT_PASSWORD:-$GITHUB_TOKEN}

if[ "$INPUT_CACHE" == "true" ]; then
  export CACHE="--cache=true --cache-ttl=${INPUT_CACHE_TTL:-168h}";
fi

export CONTEXT="--context $GITHUB_WORKSPACE"
export DOCKERFILE="--dockerfile ${INPUT_BUILD_FILE:-Dockerfile}"
export DESTINATION="--destination $REGISTRY/$IMAGE${IMAGE_NAMESPACE}:$TAG"

export ARGS="$CACHE $CONTEXT $DOCKERFILE $DESTINATION $EXTRA"

cat << EOF > /kaniko/.docker/config.json
{
    "auths": {
        "${REGISTRY}": {
            "username": "${USERNAME}",
            "password": "${PASSWORD}"
        }
    }
}
EOF

/kaniko/executor $ARGS
