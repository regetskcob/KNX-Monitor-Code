#!/bin/bash
# Self-signed certificate of the box for HTTPS; writes the fingerprint
# (SHA-256 of the certificate, base64url, see server/lib/src/box_tls.dart) to
# stdout. Runs on first boot and on update (firstboot.sh, setup.sh),
# never during the image build: every box needs its own key. An existing
# certificate is kept, otherwise the QR code would no longer match.
#
#   tls-cert.sh <directory>
set -euo pipefail

dir=${1:?Ordner angeben}
cert=$dir/cert.pem
key=$dir/key.pem

if [ ! -s "$cert" ] || [ ! -s "$key" ]; then
  # Make the directory readable for the service only once the key has its permissions.
  mkdir -p "$dir"
  chmod 0750 "$dir"
  old_umask=$(umask)
  umask 077
  # ec_param_enc: named curve; Dart's TLS stack rejects explicit parameters.
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -pkeyopt ec_param_enc:named_curve -nodes \
    -keyout "$key.new" -out "$cert.new" -days 7300 -subj "/CN=knx-box" \
    -addext "subjectAltName=DNS:knx-box.local,IP:10.42.0.1" >/dev/null 2>&1
  umask "$old_umask"
  chmod 0640 "$key.new"
  chmod 0644 "$cert.new"
  mv -f "$key.new" "$key"
  mv -f "$cert.new" "$cert"
  # The service runs as knx-box; in the dry run the group does not exist.
  chgrp knx-box "$dir" "$key" 2>/dev/null || true
fi

openssl x509 -in "$cert" -outform DER | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '='
