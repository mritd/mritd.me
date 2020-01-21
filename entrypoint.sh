#!/usr/bin/env bash

set -e

echo "blog starting..."

httpcmd -r 'git pull|chown -R nginx:nginx \/usr\/share\/nginx\/html' -t ${HTTPCMD_TOKEN} -w /usr/share/nginx/html -d

nginx -g "daemon off;"
