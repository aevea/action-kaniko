#!/busybox/sh
set -e pipefail
if [ "$INPUT_DEBUG" = "true" ]; then
    set -o xtrace
fi

export REGISTRY="${INPUT_REGISTRY:-"docker.io"}"
export IMAGE="${INPUT_IMAGE}"
export BRANCH="$(echo ${GITHUB_REF} | sed -E 's#refs/(heads|tags)/##g' | sed -e 's#/#-#g')"
export TAG=${INPUT_TAG:-$([ "$BRANCH" == "master" ] && echo latest || echo $BRANCH)}
export TAG="${TAG:-'latest'}"
export TAG="${TAG#"$INPUT_STRIP_TAG_PREFIX"}"
export USERNAME="${INPUT_USERNAME:-"$GITHUB_ACTOR"}"
export PASSWORD="${INPUT_PASSWORD:-"$GITHUB_TOKEN"}"
export REPOSITORY="${IMAGE}"
export IMAGE="${IMAGE}:${TAG}"
export CONTEXT_PATH="${INPUT_PATH}"

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

if [ "${REGISTRY}" = "ghcr.io" ]; then
    IMAGE_NAMESPACE="$(echo ${GITHUB_REPOSITORY} | tr '[:upper:]' '[:lower:]')"
    export IMAGE="${IMAGE_NAMESPACE}/${IMAGE}"
    export REPOSITORY="${IMAGE_NAMESPACE}/${REPOSITORY}"

    if [ -n "${IMAGE_LATEST}" ]; then
        export IMAGE_LATEST="${IMAGE_NAMESPACE}/${IMAGE_LATEST}"
    fi

    if [ -n "${INPUT_CACHE_REGISTRY}" ]; then
        export INPUT_CACHE_REGISTRY="${REGISTRY}/${IMAGE_NAMESPACE}/${INPUT_CACHE_REGISTRY}"
    fi
fi

if [ "${REGISTRY}" = "docker.io" ]; then
    export REGISTRY="index.${REGISTRY}/v1/"
else
    export IMAGE="${REGISTRY}/${IMAGE}"

    if [ -n "${IMAGE_LATEST}" ]; then
        export IMAGE_LATEST="${REGISTRY}/${IMAGE_LATEST}"
    fi
fi

export CACHE="${INPUT_CACHE:+"--cache=true"}"
export CACHE="${CACHE}${INPUT_CACHE_TTL:+" --cache-ttl=$INPUT_CACHE_TTL"}"
export CACHE="${CACHE}${INPUT_CACHE_REGISTRY:+" --cache-repo=$INPUT_CACHE_REGISTRY"}"
export CACHE="${CACHE}${INPUT_CACHE_DIRECTORY:+" --cache-dir=$INPUT_CACHE_DIRECTORY"}"
export CONTEXT="--context ${GITHUB_WORKSPACE}/${CONTEXT_PATH}"
export DOCKERFILE="--dockerfile ${CONTEXT_PATH}/${INPUT_BUILD_FILE:-Dockerfile}"
export TARGET="${INPUT_TARGET:+"--target=$INPUT_TARGET"}"
export ARG_DIGEST="--digest-file /kaniko/digest --image-name-tag-with-digest-file=/kaniko/image-tag-digest"

if [ -n "${INPUT_SKIP_UNCHANGED_DIGEST}" ]; then
    export DESTINATION="--no-push --tarPath image.tar --destination ${IMAGE}"
else
    export DESTINATION="--destination $IMAGE"
    if [ -n "${IMAGE_LATEST}" ]; then
        export DESTINATION="${DESTINATION} --destination ${IMAGE_LATEST}"  
    fi
fi

export ARGS="${CACHE} ${CONTEXT} ${DOCKERFILE} ${TARGET} ${ARG_DIGEST} ${DESTINATION} ${INPUT_EXTRA_ARGS}"

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

# https://github.com/GoogleContainerTools/kaniko/issues/1349
/kaniko/executor --reproducible --force ${ARGS}

echo "::set-output name=DIGEST::$(cat /kaniko/digest)"
echo "::set-output name=DIGEST_IMAGE_TAG::$(cat /kaniko/image-tag-digest)"

export IMAGE_REFRESHED="true"
if [ -n "${INPUT_SKIP_UNCHANGED_DIGEST}" ]; then
    DIGEST="$(cat /kaniko/digest)"
    export DIGEST
    /kaniko/crane auth login "${REGISTRY}" -u "${USERNAME}" -p "${PASSWORD}"
    REMOTE="$(crane digest "${REGISTRY}/${REPOSITORY}:${TAG}" || true)"
    export REMOTE

    if [ "${DIGEST}" = "${REMOTE}" ]; then
        echo "Digest hasn't changed, skipping, ${DIGEST}"
        export IMAGE_REFRESHED="false" 
    else
        echo "Pushing image..."  
        /kaniko/crane push image.tar "${IMAGE}"

        if [ -n "${IMAGE_LATEST}" ]; then
            echo "Tagging latest..."
            /kaniko/crane tag "${IMAGE}" "${TAG}"
        fi
    fi
    echo "::set-output name=IMAGE_REFRESHED::${IMAGE_REFRESHED}"
    echo "Done "
fi
