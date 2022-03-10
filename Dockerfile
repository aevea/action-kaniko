FROM alpine as certs

RUN apk --update add ca-certificates

FROM gcr.io/kaniko-project/executor:v1.7.0-debug

SHELL ["/busybox/sh", "-c"]

RUN wget -O /kaniko/jq \
    https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && \
    chmod +x /kaniko/jq && \
    wget -O /kaniko/reg \
    https://github.com/genuinetools/reg/releases/download/v0.16.1/reg-linux-386 && \
    chmod +x /kaniko/reg && \
    wget -O /crane.tar.gz \ 
    https://github.com/google/go-containerregistry/releases/download/v0.1.1/go-containerregistry_Linux_x86_64.tar.gz && \
    tar -xvzf /crane.tar.gz crane -C /kaniko && \
    rm /crane.tar.gz && \
    wget -O /yq_linux_386.tar.gz https://github.com/mikefarah/yq/releases/download/v4.15.1/yq_linux_386.tar.gz && \
    tar -zxvf /yq_linux_386.tar.gz ./yq_linux_386 -C /kaniko && \
    mv /kaniko/yq_linux_386 /kaniko/yq && \
    rm /yq_linux_386.tar.gz

COPY entrypoint.sh /
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

ENTRYPOINT ["/entrypoint.sh"]

LABEL repository="https://github.com/ohioit/action-kaniko" \
    maintainer="Ohio University"
