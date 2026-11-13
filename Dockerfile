# Builds the Busclear image from this repository alone: web app, server and
# packages, without a local Flutter or Dart.
#
#   docker build -t knx-monitor .
#   docker build -t knx-monitor --build-arg BUILD_VERSION=1.9.7 .
#
# The result is the same image as ghcr.io/regetskcob/knx-monitor, for Docker
# without Home Assistant (tool/public-repo/docker/compose.yaml: replace the
# image line with "image: knx-monitor"). The published images are built by
# .github/workflows/addon.yml from ha-addon/knx_monitor/Dockerfile, which needs
# the prebuilt web app; .github/workflows/docker.yml checks this file.

# Flutter as in the CI (flutter-version in .github/workflows), pinned by commit:
# a moved tag aborts the build.
ARG FLUTTER_VERSION=3.47.6
ARG FLUTTER_COMMIT=5fc346839b5d0eef006ed8404392afb4dfae428d

# The web app is the same on every architecture, so it is built on the build
# machine (no emulation for an arm64 image on amd64 and vice versa).
FROM --platform=$BUILDPLATFORM dart:3.13.7@sha256:854f3c50b1cbd4a5a54c9fa67d4f5b6702ac49b4a26d21a80e7712a72528b215 AS web
ARG FLUTTER_VERSION
ARG FLUTTER_COMMIT
RUN apt-get update && apt-get install -y --no-install-recommends git unzip xz-utils && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /flutter \
  && test "$(git -C /flutter rev-parse HEAD)" = "$FLUTTER_COMMIT"
ENV PATH=/flutter/bin:$PATH
RUN flutter config --no-analytics --no-cli-animations >/dev/null && flutter precache --web
WORKDIR /src
# Dependencies first, so a code change does not download them again.
COPY pubspec.yaml pubspec.lock ./
COPY third_party/ third_party/
RUN flutter pub get --enforce-lockfile
COPY . .
# Without debug symbols and the WebAssembly renderer, as tool/build_ha_addon.sh.
RUN flutter gen-l10n && flutter build web --release --no-web-resources-cdn \
  && find build/web \( -name '*.symbols' -o -name 'skwasm*' \) -delete

# The server, as in ha-addon/knx_monitor/Dockerfile but from the repository root.
FROM dart:3.13.7@sha256:854f3c50b1cbd4a5a54c9fa67d4f5b6702ac49b4a26d21a80e7712a72528b215 AS server
# Time zones: the history's day change should be local (TZ).
RUN apt-get update && apt-get install -y --no-install-recommends tzdata && rm -rf /var/lib/apt/lists/*
WORKDIR /src/ha-addon/knx_monitor/server
COPY ha-addon/knx_monitor/server/pubspec.yaml ha-addon/knx_monitor/server/pubspec.lock ./
RUN dart pub get --enforce-lockfile
COPY ha-addon/knx_monitor/server/ ./
RUN dart compile exe bin/server.dart -o /server

FROM scratch
# Version shown in the app and on the MQTT device.
ARG BUILD_VERSION=dev
COPY --from=server /runtime/ /
COPY --from=server /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=server /server /app/server
COPY --from=web /src/build/web/ /app/web/
COPY ha-addon/knx_monitor/card/ /app/card/
ENV PORT=8765 WEB_DIR=/app/web DATA_DIR=/data/app ADDON_VERSION=$BUILD_VERSION
CMD ["/app/server"]
