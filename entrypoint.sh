#!/busybox/sh
set -e pipefail

export REGISTRY=${INPUT_REGISTRY:-"docker.io"}
export IMAGE=${INPUT_IMAGE}
export BRANCH=$(echo ${GITHUB_REF} | sed -e "s/refs\/heads\///g" | sed -e "s/\//-/g")
export TAG=${INPUT_TAG:-$([ "$BRANCH" == "master" ] && echo latest || echo $BRANCH)}
export TAG=${TAG:-"latest"}
export USERNAME=${INPUT_USERNAME:-$GITHUB_ACTOR}
export PASSWORD=${INPUT_PASSWORD:-$GITHUB_TOKEN}
export IMAGE=$IMAGE:$TAG

function sanitize() {
    if [ -z "${1}" ]; then
        echo >&2 "Unable to find the ${2}. Did you set with.${2}?"
        exit 1
    fi
}

sanitize "${REGISTRY}" "registry"
sanitize "${USERNAME}" "username"
sanitize "${PASSWORD}" "password"
sanitize "${IMAGE}" "image"
sanitize "${TAG}" "tag"

if [ "$REGISTRY" == "docker.pkg.github.com" ]; then
    export IMAGE="$GITHUB_REPOSITORY/$IMAGE"

    if [ -z $INPUT_CACHE_REGISTRY ]; then
        export INPUT_CACHE_REGISTRY="$GITHUB_REPOSITORY/$INPUT_CACHE_REGISTRY"
    fi
fi

if [ "$REGISTRY" == "docker.io" ]; then
    export REGISTRY="index.${REGISTRY}/v1/"
else
    export IMAGE="$REGISTRY/$IMAGE"
fi

export CACHE=${INPUT_CACHE:+"--cache=true"}
export CACHE=$CACHE${INPUT_CACHE_TTL:+" --cache-ttl=$INPUT_CACHE_TTL"}
export CACHE=$CACHE${INPUT_CACHE_REGISTRY:+" --cache-repo=$INPUT_CACHE_REGISTRY"}
export CACHE=$CACHE${INPUT_CACHE_DIRECTORY:+" --cache-dir=$INPUT_CACHE_DIRECTORY"}
export CONTEXT="--context $GITHUB_WORKSPACE"
export DOCKERFILE="--dockerfile ${INPUT_BUILD_FILE:-Dockerfile}"
export DESTINATION="--destination $IMAGE"

export ARGS="$CACHE $CONTEXT $DOCKERFILE $DESTINATION $INPUT_EXTRA_ARGS"
echo $ARGS

cat <<EOF >/kaniko/.docker/config.json
{
    "auths": {
        "https://${REGISTRY}": {
            "username": "${USERNAME}",
            "password": "${PASSWORD}"
        }
    }
}
EOF

/kaniko/executor $ARGS
