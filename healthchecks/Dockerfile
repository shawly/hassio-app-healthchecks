ARG BUILD_FROM=ghcr.io/hassio-addons/base:21.0.2
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Setup base
ARG HEALTHCHECKS_VERSION="4.3"
ARG UWSGI_VERSION="2.0.31"
ARG APPRISE_VERSION="1.12.0"
RUN \
    apk add --no-cache --virtual .build-dependencies \
        build-base=0.5-r4 \
        curl-dev=8.21.0-r0 \
        libffi-dev=3.5.2-r1 \
        libpq-dev=18.6-r0 \
        linux-headers=7.0.0-r1 \
        openssl-dev=3.5.7-r0 \
        pcre2-dev=10.47-r1 \
        py3-pip=26.1.2-r0 \
        python3-dev=3.14.7-r1 \
    \
    && apk add --no-cache \
        libpq=18.6-r0 \
        nginx=1.30.4-r1 \
        python3=3.14.7-r1 \
    \
    && mkdir -p /opt/healthchecks \
    && curl -L -s "https://github.com/healthchecks/healthchecks/archive/refs/tags/v${HEALTHCHECKS_VERSION}.tar.gz" \
        | tar zxf - --strip-components=1 -C /opt/healthchecks \
    \
    && python3 -m venv /opt/venv \
    \
    && PYCURL_SSL_LIBRARY=openssl \
       /opt/venv/bin/pip install --no-cache-dir \
        -r /opt/healthchecks/requirements.txt \
        "apprise==${APPRISE_VERSION}" \
        "uwsgi==${UWSGI_VERSION}" \
    \
    && rm -fr \
        /opt/healthchecks/.github \
        /opt/healthchecks/docker \
        /opt/healthchecks/search.db \
        /opt/healthchecks/stuff \
    \
    && apk del --no-cache --purge .build-dependencies \
    && rm -fr \
        /tmp/* \
        /root/.cache

# Patch the upstream source. See the script for what and why.
COPY patches /tmp/patches
RUN \
    /opt/venv/bin/python /tmp/patches/absolute-url-script-name.py \
    && rm -fr /tmp/patches

# Copy root filesystem
COPY rootfs /

# Collect the static assets. django-compressor is deliberately not run here:
# its offline manifest bakes in a single fixed URL prefix, and this app
# serves the app under two of them. See DOCS.md.
WORKDIR /opt/healthchecks
RUN \
    DEBUG=False SECRET_KEY=build-key \
        /opt/venv/bin/python manage.py collectstatic --noinput \
    && rm -fr /root/.cache

# Build arguments
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

# Labels
LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="shawly <shawly@users.noreply.github.com>" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="shawly's Home Assistant Apps" \
    org.opencontainers.image.authors="shawly <shawly@users.noreply.github.com>" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://github.com/shawly/hassio-addons" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/main/README.md" \
    org.opencontainers.image.created=${BUILD_DATE} \
    org.opencontainers.image.revision=${BUILD_REF} \
    org.opencontainers.image.version=${BUILD_VERSION}
