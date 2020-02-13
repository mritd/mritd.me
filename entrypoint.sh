#!/bin/bash

set -e

rm -rf /usr/share/nginx/html
git clone -b gh-pages https://github.com/mritd/mritd.me.git /usr/share/nginx/html

echo "blog starting..."

httpcmd -r 'git pull|chown -R nginx:nginx \/usr\/share\/nginx\/html' -t ${HTTPCMD_TOKEN} -w /usr/share/nginx/html -d
nginx -g "daemon off;"
