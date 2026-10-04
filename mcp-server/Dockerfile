FROM alpine:3.24
LABEL image.authors="Victor Fernandez III"
WORKDIR /home/wintermute/
COPY wintermute/pyproject.toml pyproject.toml
COPY wintermute/main.py main.py
COPY wintermute/uv.lock uv.lock
ENV UV_PYTHON_INSTALL_DIR=/home/wintermute/.uv-python
RUN apk add --no-cache python3=3.14.8-r0 uv=0.11.19-r0 &&\
    apk add --no-cache --virtual .build-time-dependencies curl=8.22.0-r0 &&\
    apk upgrade --no-cache libcrypto3 libssl3 &&\
    curl --fail --location --retry 3 \
        https://github.com/cyberphor/skills/releases/latest/download/skills.tar.gz \
        --output /tmp/skills.tar.gz &&\
    tar -xzf /tmp/skills.tar.gz &&\
    rm -rf /tmp/skills.tar.gz &&\
    apk del .build-time-dependencies &&\
    uv sync --frozen --python /usr/bin/python3 &&\
    addgroup -g 1000 wintermute &&\
    adduser -D -G wintermute -u 1000 wintermute -h /home/wintermute/ &&\
    chown -R wintermute:wintermute /home/wintermute/
ENV PATH="/home/wintermute/.venv/bin:$PATH"
USER 1000
EXPOSE 8002
CMD [ "python", "-m", "main" ]
