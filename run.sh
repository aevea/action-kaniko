# Use this to build and run the docker image locally

set -e
WORKSPACE_DIR=/workspace
docker build -t action-kaniko ./
docker run --rm \
    -w ${WORKSPACE_DIR} \
    -v $PWD/ais-build.yaml:${WORKSPACE_DIR}/ais-build.yaml \
    --env-file .env \
    action-kaniko