FROM alpine as certs

RUN apk --update add ca-certificates

FROM gcr.io/kaniko-project/executor:v1.19.2-debug

SHELL ["/busybox/sh", "-c"]

RUN wget -O /kaniko/jq \
    https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux64 && \
    chmod +x /kaniko/jq && \
    wget -O /kaniko/reg \
    https://github.com/genuinetools/reg/releases/download/v0.16.1/reg-linux-386 && \
    chmod +x /kaniko/reg && \
    wget -O /crane.tar.gz \
    https://github.com/google/go-containerregistry/releases/download/v0.17.0/go-containerregistry_Linux_x86_64.tar.gz && \
    tar -xvzf /crane.tar.gz crane -C /kaniko && \
    rm /crane.tar.gz

COPY entrypoint.sh /
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

ENTRYPOINT ["/entrypoint.sh"]

LABEL repository="https://github.com/aevea/action-kaniko" \
    maintainer="Alex Viscreanu <alexviscreanu@gmail.com>"
