# syntax=docker/dockerfile:1

FROM python:3.14-slim-trixie AS builder

ARG CURL_VERSION=8.22.0

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBUG=False \
    LD_LIBRARY_PATH="/opt/curl/lib" \
    PATH="/opt/venv/bin:/opt/curl/bin:$PATH"

WORKDIR /app

# Build tools remain in the builder stage.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        gnupg \
        gpgv \
        xz-utils \
        ca-certificates \
        libpq-dev \
        libssl-dev \
        zlib1g-dev \
        libbrotli-dev \
        libzstd-dev \
        libidn2-dev \
        libpsl-dev \
        libnghttp2-dev \
        libssh2-1-dev \
        libldap-dev \
        libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*

# Download source, signature, and the release manager's public key.
ADD https://curl.se/download/curl-${CURL_VERSION}.tar.xz /tmp/curl.tar.xz
ADD https://curl.se/download/curl-${CURL_VERSION}.tar.xz.asc /tmp/curl.tar.xz.asc
ADD https://daniel.haxx.se/mykey.asc /tmp/curl-release-key.asc

# Verify using only the pinned signing key, then build without RTMP.
RUN gpg --batch --import /tmp/curl-release-key.asc \
    && gpg --batch --export \
        27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2 \
        > /tmp/curl-keyring.gpg \
    && gpgv --keyring /tmp/curl-keyring.gpg \
        /tmp/curl.tar.xz.asc /tmp/curl.tar.xz \
    && mkdir -p /tmp/curl-src \
    && tar -xJf /tmp/curl.tar.xz \
        --strip-components=1 -C /tmp/curl-src \
    && cd /tmp/curl-src \
    && ./configure \
        --prefix=/opt/curl \
        --libdir=/opt/curl/lib \
        --enable-shared \
        --disable-static \
        --with-openssl \
        --without-gnutls \
        --without-librtmp \
        --with-libpsl \
        --with-libidn2 \
        --with-brotli \
        --with-zstd \
        --with-nghttp2 \
        --with-libssh2 \
        --with-gssapi \
        --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
        --with-ca-path=/etc/ssl/certs \
    && make -j2 \
    && make install \
    && install -D -m 644 COPYING \
        /opt/curl/share/licenses/curl/COPYING \
    && cd /app \
    && rm -rf /tmp/curl-src \
        /tmp/curl.tar.xz \
        /tmp/curl.tar.xz.asc \
        /tmp/curl-release-key.asc \
        /tmp/curl-keyring.gpg

RUN python -m venv /opt/venv

COPY requirements.txt ./

# Build PycURL against our verified libcurl.
# Keep pip's cache outside the image layers.
RUN --mount=type=cache,id=week7-pip-arm64-py314-curl-${CURL_VERSION},target=/root/.cache/pip \
    PYCURL_CURL_CONFIG=/opt/curl/bin/curl-config \
    PYCURL_SSL_LIBRARY=openssl \
        python -m pip install --no-binary=pycurl \
            -r requirements.txt \
    && python -m pip check

COPY . .

RUN SECRET_KEY=build-only-placeholder \
        python manage.py compress \
    && SECRET_KEY=build-only-placeholder \
        python manage.py collectstatic --noinput \
    && python -m pip uninstall -y pip

FROM python:3.14-slim-trixie AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBUG=False \
    LD_LIBRARY_PATH="/opt/curl/lib" \
    PATH="/opt/venv/bin:/opt/curl/bin:$PATH"

WORKDIR /app

# Install runtime libraries.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libpq5 \
        libssl3t64 \
        zlib1g \
        libbrotli1 \
        libzstd1 \
        libidn2-0 \
        libpsl5t64 \
        libnghttp2-14 \
        libssh2-1t64 \
        libldap2 \
        libgssapi-krb5-2 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && /usr/local/bin/python -m pip uninstall -y pip \
    && rm -rf /usr/local/lib/python3.14/ensurepip

RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app \
        --create-home --shell /usr/sbin/nologin app

# Copy curl before changing its permissions.
COPY --from=builder /opt/curl/lib/libcurl.so* /opt/curl/lib/
COPY --from=builder /opt/curl/bin/curl /opt/curl/bin/curl
COPY --from=builder /opt/curl/share/licenses/ /opt/curl/share/licenses/

# Copy Python dependencies once.
COPY --from=builder /opt/venv /opt/venv

# Both dependency directories now exist.
RUN chmod -R a+rX,go-w /opt/venv /opt/curl

# Handle application files separately.
COPY --from=builder --chown=root:root /app /app

RUN chmod -R a+rX,go-w /app

USER app

EXPOSE 8000

CMD ["gunicorn", "hc.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "--error-logfile", "-"]
