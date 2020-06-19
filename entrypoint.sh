#!/busybox/sh
set -e pipefail

export REGISTRY=${INPUT_REGISTRY:-"docker.io"}
export IMAGE=${INPUT_IMAGE}
export BRANCH=$(echo ${GITHUB_REF} | sed -E "s/refs\/(heads|tags)\///g" | sed -e "s/\//-/g")
export TAG=${INPUT_TAG:-$([ "$BRANCH" == "master" ] && echo latest || echo $BRANCH)}
export TAG=${TAG:-"latest"}
export TAG=${TAG#$INPUT_STRIP_TAG_PREFIX}
export USERNAME=${INPUT_USERNAME:-$GITHUB_ACTOR}
export PASSWORD=${INPUT_PASSWORD:-$GITHUB_TOKEN}
export IMAGE=$IMAGE:$TAG

function ensure() {
    if [ -z "${1}" ]; then
        echo >&2 "Unable to find the ${2} variable. Did you set with.${2}?"
        exit 1
    fi
}

ensure "${REGISTRY}" "registry"
ensure "${USERNAME}" "username"
ensure "${PASSWORD}" "password"
ensure "${IMAGE}" "image"
ensure "${TAG}" "tag"

if [ "$REGISTRY" == "docker.pkg.github.com" ]; then
    IMAGE_NAMESPACE="$(echo $GITHUB_REPOSITORY | tr '[:upper:]' '[:lower:]')"
    export IMAGE="$IMAGE_NAMESPACE/$IMAGE"

    if [ ! -z $INPUT_CACHE_REGISTRY ]; then
        export INPUT_CACHE_REGISTRY="$REGISTRY/$IMAGE_NAMESPACE/$INPUT_CACHE_REGISTRY"
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
export DESTINATION="--no-push"

export ARGS="$CACHE $CONTEXT $DOCKERFILE $DESTINATION $INPUT_EXTRA_ARGS"

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

/kaniko/executor --digest-file digest --reproducible $ARGS

export DIGEST=$(cat digest)
export REMOTE=$(reg digest "$IMAGE" | tail -1)

if [ ! -z $INPUT_SKIP_UNCHANGED_DIGEST ]; then
    if [ "$DIGEST" == "$REMOTE" ]; then
        echo "Digest hasn't changed, skipping, $DIGEST"
        exit 0
    fi
fi

export DESTINATION="--destination $IMAGE"
export ARGS="$CACHE $CONTEXT $DOCKERFILE $DESTINATION $INPUT_EXTRA_ARGS"

echo "Pushing image..."

/kaniko/executor --reproducible $ARGS >/dev/null 2>&1

echo "Done 🎉️"
