#!/usr/bin/env bash
set -Eeo pipefail
# TODO add "-u"

# install additional gems for Gemfile.local and plugins
bundle check || bundle install
rake generate_secret_token
rake db:migrate
rake redmine:plugins:migrate
rm -f tmp/pids/server.pid

exec "$@"
