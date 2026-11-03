# Compile the server (the web app is prebuilt in ./web, see tool/build_ha_addon.sh).
# Fixed Dart version (like the app's Flutter), pinned by digest: a moved tag
# changes nothing. Dependabot bumps both monthly.
FROM dart:3.13.6@sha256:bf07cd831c34d7cef047bcd50803fa38e3af59664a276440893ca9db77014ca0 AS build
# Time zones: Supervisor sets TZ, the history's day change should be local.
RUN apt-get update && apt-get install -y --no-install-recommends tzdata && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY server/pubspec.yaml server/pubspec.lock ./
RUN dart pub get --enforce-lockfile
COPY server/ ./
RUN dart compile exe bin/server.dart -o /server

FROM scratch
# Version for the MQTT device in Home Assistant (workflow addon.yml).
ARG BUILD_VERSION=dev
COPY --from=build /runtime/ /
COPY --from=build /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=build /server /app/server
COPY web/ /app/web/
COPY card/ /app/card/
ENV PORT=8765 WEB_DIR=/app/web DATA_DIR=/data/app ADDON_VERSION=$BUILD_VERSION
CMD ["/app/server"]
