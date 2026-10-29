#!/bin/sh
# Startup contract for the Nginx-only deployment script.
set -eu
case "${PORTFOLIO_COMMIT:-}" in
    ''|*[!0-9a-f]*) echo 'PORTFOLIO_COMMIT must be a full lowercase Git commit SHA.' >&2; exit 1 ;;
esac
[ "${#PORTFOLIO_COMMIT}" -eq 40 ]
apk add --no-cache git
# These are fixed, container-local paths; deploy refuses mounts over site/config.
rm -rf /tmp/portfolio-source
git init /tmp/portfolio-source
git -C /tmp/portfolio-source remote add origin https://github.com/clamm0363/Portfolio-Page.git
git -C /tmp/portfolio-source fetch --depth 1 origin "$PORTFOLIO_COMMIT"
git -C /tmp/portfolio-source checkout --detach FETCH_HEAD
[ "$(git -C /tmp/portfolio-source rev-parse HEAD)" = "$PORTFOLIO_COMMIT" ]
cp /tmp/portfolio-source/index.html /usr/share/nginx/html/index.html
rm -rf /usr/share/nginx/html/assets
cp -R /tmp/portfolio-source/assets /usr/share/nginx/html/
cp /tmp/portfolio-source/nginx/nginx.conf /etc/nginx/nginx.conf
printf '{"commit":"%s"}\n' "$PORTFOLIO_COMMIT" > /usr/share/nginx/html/release.json
nginx -t
rm -rf /tmp/portfolio-source
exec nginx -g 'daemon off;'
