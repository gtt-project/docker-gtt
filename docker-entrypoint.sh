#!/bin/bash

if [[ -v REDMINE_LANG ]];
then
echo "REDMINE_LANG is already set: ${REDMINE_LANG}"
else
echo "Set REDMINE_LANG variable to: en"
export REDMINE_LANG="en"
fi

bundle exec rake generate_secret_token
bundle config set without 'development test'
bundle install
bundle exec rake db:create
bundle exec rake db:migrate
bundle exec rake redmine:plugins:migrate

# Load default data and settings
bundle exec rake redmine:load_default_data

# Cleanup
rm -f tmp/pids/server.pid

exec "$@"
