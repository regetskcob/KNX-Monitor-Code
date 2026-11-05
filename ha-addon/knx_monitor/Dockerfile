# Compile the server (the web app is prebuilt in ./web, see tool/build_ha_addon.sh).
# Fixed Dart version (like the app's Flutter), pinned by digest: a moved tag
# changes nothing. Dependabot bumps both monthly.
FROM dart:3.13.7@sha256:517cbeb4612c4dff11c983edea521d5aef3f47a674c23684fad5e89803ca5b1c AS build
# Time zones: Supervisor sets TZ, the history's day change should be local.
RUN apt-get update && apt-get install -y --no-install-recommends tzdata && rm -rf /var/lib/apt/lists/*
# The server depends on packages/knx by the path ../../../packages/knx. The
# build context is only this folder, so tool/addon_packages.sh copies the
# repository's packages/ into ./packages (gitignored) before every build; here
# both land in the same layout as in the repository.
WORKDIR /src/ha-addon/knx_monitor/server
COPY packages/ /src/packages/
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
