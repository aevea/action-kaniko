FROM gcr.io/kaniko-project/executor:debug

COPY entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]

LABEL repository="https://github.com/aevea/action-kaniko" \
    maintainer="Alex Viscreanu <alexviscreanu@gmail.com>"
