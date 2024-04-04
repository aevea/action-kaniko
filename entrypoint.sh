#!/busybox/sh
set -e pipefail
if [ "$INPUT_DEBUG" = "true" ]; then
    set -o xtrace
fi

export REGISTRY="${INPUT_REGISTRY:-"docker.io"}"
export IMAGE="$INPUT_IMAGE"
export BRANCH=$(echo "$GITHUB_REF" | sed -E "s/refs\/(heads|tags)\///g" | sed -e "s/\//-/g")
export TAG=${INPUT_TAG:-$([ "$BRANCH" = "master" ] && echo latest || echo "$BRANCH")}
export TAG="${TAG:-"latest"}"
export TAG="${TAG#$INPUT_STRIP_TAG_PREFIX}"
export USERNAME="${INPUT_USERNAME:-$GITHUB_ACTOR}"
export PASSWORD="${INPUT_PASSWORD:-$GITHUB_TOKEN}"
export REPOSITORY="$IMAGE"
export IMAGE="${IMAGE}:${TAG}"
export CONTEXT_PATH="$INPUT_PATH"

if [ "$INPUT_TAG_WITH_LATEST" = "true" ]; then
    export IMAGE_LATEST="${REPOSITORY}:latest"
fi

ensure() {
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
ensure "${CONTEXT_PATH}" "path"

if [ "$REGISTRY" = "ghcr.io" ]; then
    IMAGE_NAMESPACE="$(echo $GITHUB_REPOSITORY | tr '[:upper:]' '[:lower:]')"
    # Set `/` separator, unless image is pre-fixed with dash or slash
    [ -n "$REPOSITORY" ] && [[ ! "$REPOSITORY" =~ ^[-/] ]] && SEPARATOR="/"
    export IMAGE="$IMAGE_NAMESPACE$SEPARATOR$IMAGE"
    export REPOSITORY="$IMAGE_NAMESPACE$SEPARATOR$REPOSITORY"

    if [ -n "$IMAGE_LATEST" ]; then
        export IMAGE_LATEST="${IMAGE_NAMESPACE}/${IMAGE_LATEST}"
    fi

    if [ -n "$INPUT_CACHE_REGISTRY" ]; then
        export INPUT_CACHE_REGISTRY="${REGISTRY}/${IMAGE_NAMESPACE}/${INPUT_CACHE_REGISTRY}"
    fi
fi

if [ "$REGISTRY" = "docker.io" ]; then
    export REGISTRY="index.${REGISTRY}/v1/"
else
    export IMAGE="${REGISTRY}/${IMAGE}"

    if [ -n "$IMAGE_LATEST" ]; then
        export IMAGE_LATEST="${REGISTRY}/${IMAGE_LATEST}"
    fi
fi

export CACHE="${INPUT_CACHE:+"--cache=true"}"
export CACHE="$CACHE"${INPUT_CACHE_TTL:+" --cache-ttl=$INPUT_CACHE_TTL"}
export CACHE="$CACHE"${INPUT_CACHE_REGISTRY:+" --cache-repo=$INPUT_CACHE_REGISTRY"}
export CACHE="$CACHE"${INPUT_CACHE_DIRECTORY:+" --cache-dir=$INPUT_CACHE_DIRECTORY"}
export CONTEXT="--context $GITHUB_WORKSPACE/$CONTEXT_PATH"
export DOCKERFILE="--dockerfile $CONTEXT_PATH/${INPUT_BUILD_FILE:-Dockerfile}"
export TARGET=${INPUT_TARGET:+"--target=$INPUT_TARGET"}
export DIGEST="--digest-file /kaniko/digest --image-name-tag-with-digest-file=/kaniko/image-tag-digest"

if [ -n "$INPUT_SKIP_UNCHANGED_DIGEST" ]; then
    export DESTINATION="--no-push --tarPath image.tar --destination $IMAGE"
else
    export DESTINATION="--destination $IMAGE"
    if [ -n "$IMAGE_LATEST" ]; then
        export DESTINATION="$DESTINATION --destination $IMAGE_LATEST"
    fi
fi

export ARGS="$CACHE $CONTEXT $DOCKERFILE $TARGET $DIGEST $DESTINATION $INPUT_EXTRA_ARGS"

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

# https://github.com/GoogleContainerTools/kaniko/issues/1803
# https://github.com/GoogleContainerTools/kaniko/issues/1349
export IFS=''
# Removes a trailing new line
ARGS=$(echo "${ARGS}" | sed 's/\n*$//')
kaniko_cmd="/kaniko/executor ${ARGS} --reproducible --force"
echo "Running kaniko command ${kaniko_cmd}"
eval "${kaniko_cmd}"

echo "image=$IMAGE" >> "$GITHUB_OUTPUT"
echo "digest=$(cat /kaniko/digest)" >> "$GITHUB_OUTPUT"
echo "image-tag-digest<<EOF" >>"$GITHUB_OUTPUT"
echo "$(cat /kaniko/image-tag-digest)" >>"$GITHUB_OUTPUT"
echo 'EOF' >>"$GITHUB_OUTPUT"


if [ -n "$INPUT_SKIP_UNCHANGED_DIGEST" ]; then
    export DIGEST="$(cat /kaniko/digest)"

    /kaniko/crane auth login "$REGISTRY" -u "$USERNAME" -p "$PASSWORD"

    export REMOTE=$(crane digest "${REGISTRY}/${REPOSITORY}:latest")

    if [ "$DIGEST" = "$REMOTE" ]; then
        echo "refreshed=false" >> "$GITHUB_OUTPUT"
        echo "Digest hasn't changed, skipping, $DIGEST"
        echo "Done 🎉️"
        exit 0
    fi

    echo "Pushing image..."

    /kaniko/crane push image.tar "$IMAGE"

    if [ -n "$IMAGE_LATEST" ]; then
        echo "Tagging latest..."
        /kaniko/crane tag "$IMAGE" latest
    fi

    echo "refreshed=false" >> "$GITHUB_OUTPUT"
    echo "Done 🎉️"
fi
