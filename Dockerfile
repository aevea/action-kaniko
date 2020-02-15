FROM gcr.io/kaniko-project/executor:debug

COPY entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]
