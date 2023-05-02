#!/busybox/sh
set -e pipefail
if [[ "$INPUT_DEBUG" == "true" ]]; then
    set -o xtrace
fi

export REGISTRY=${INPUT_REGISTRY:-"docker.io"}
export IMAGE=${INPUT_IMAGE}
export BRANCH=$(echo ${GITHUB_REF} | sed -E "s/refs\/(heads|tags)\///g" | sed -e "s/\//-/g")
export TAGS=${INPUT_TAGS:-$([ "$BRANCH" == "master" ] && echo latest || echo $BRANCH)}
export TAGS=${TAGS:-"latest"}
export TAGS=${TAGS#$INPUT_STRIP_TAG_PREFIX}
export USERNAME=${INPUT_USERNAME:-$GITHUB_ACTOR}
export PASSWORD=${INPUT_PASSWORD:-$GITHUB_TOKEN}
export REPOSITORY=$IMAGE
export CONTEXT_PATH=${INPUT_PATH}

if [[ "$INPUT_TAG_WITH_LATEST" == "true" ]]; then
    export IMAGE_LATEST="$REPOSITORY:latest"
fi

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
ensure "${TAGS}" "tags"
ensure "${CONTEXT_PATH}" "path"

# Set credentials here
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

tags=$(echo $TAGS | tr "," "\n")

for tag in $tags; do

    export TAGGED_IMAGE=$IMAGE:$tag

    if [ "$REGISTRY" == "ghcr.io" ]; then
        IMAGE_NAMESPACE="$(echo $GITHUB_REPOSITORY | tr '[:upper:]' '[:lower:]')"
        export TAGGED_IMAGE="$IMAGE_NAMESPACE/$IMAGE"
        export REPOSITORY="$IMAGE_NAMESPACE/$REPOSITORY"

        if [ ! -z $IMAGE_LATEST ]; then
            export IMAGE_LATEST="$IMAGE_NAMESPACE/$IMAGE_LATEST"
        fi

        if [ ! -z $INPUT_CACHE_REGISTRY ]; then
            export INPUT_CACHE_REGISTRY="$REGISTRY/$IMAGE_NAMESPACE/$INPUT_CACHE_REGISTRY"
        fi
    fi

    if [ "$REGISTRY" == "docker.io" ]; then
        export REGISTRY="index.${REGISTRY}/v1/"
    else
        export TAGGED_IMAGE="$REGISTRY/$TAGGED_IMAGE"

        if [ ! -z $IMAGE_LATEST ]; then
            export IMAGE_LATEST="$REGISTRY/$IMAGE_LATEST"
        fi
    fi

    export DESTINATIONS="$DESTINATIONS --destination $TAGGED_IMAGE"

done

export CACHE=${INPUT_CACHE:+"--cache=true"}
export CACHE=$CACHE${INPUT_CACHE_TTL:+" --cache-ttl=$INPUT_CACHE_TTL"}
export CACHE=$CACHE${INPUT_CACHE_REGISTRY:+" --cache-repo=$INPUT_CACHE_REGISTRY"}
export CACHE=$CACHE${INPUT_CACHE_DIRECTORY:+" --cache-dir=$INPUT_CACHE_DIRECTORY"}
export CONTEXT="--context $GITHUB_WORKSPACE/$CONTEXT_PATH"
export DOCKERFILE="--dockerfile $CONTEXT_PATH/${INPUT_BUILD_FILE:-Dockerfile}"
export TARGET=${INPUT_TARGET:+"--target=$INPUT_TARGET"}

if [ ! -z $INPUT_SKIP_UNCHANGED_DIGEST ]; then
    export DESTINATION="--digest-file digest --no-push --tarPath image.tar $DESTINATIONS"
else
    export DESTINATION=$DESTINATIONS
    if [ ! -z $IMAGE_LATEST ]; then
        export DESTINATION="$DESTINATIONS --destination $IMAGE_LATEST"
    fi
fi

export ARGS="$CACHE $CONTEXT $DOCKERFILE $TARGET $DESTINATION $INPUT_EXTRA_ARGS"

# https://github.com/GoogleContainerTools/kaniko/issues/1349
/kaniko/executor --reproducible --force $ARGS

if [ ! -z $INPUT_SKIP_UNCHANGED_DIGEST ]; then
    export DIGEST=$(cat digest)

    /kaniko/crane auth login $REGISTRY -u $USERNAME -p $PASSWORD

    export REMOTE=$(crane digest $REGISTRY/${REPOSITORY}:latest)

    if [ "$DIGEST" == "$REMOTE" ]; then
        echo "Digest hasn't changed, skipping, $DIGEST"
        echo "Done 🎉️"
        exit 0
    fi

    echo "Pushing image..."

    /kaniko/crane push image.tar $TAGGED_IMAGE

    if [ ! -z $IMAGE_LATEST ]; then
        echo "Tagging latest..."
        /kaniko/crane tag $IMAGE latest
    fi

    echo "Done 🎉️"
fi
