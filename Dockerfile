# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# GTT Builder
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
FROM node:16-bullseye-slim as gtt-builder

WORKDIR /app

COPY plugins/redmine_gtt/ ./redmine_gtt/

RUN apt update; \
    apt install -y git; \
    cd redmine_gtt; \
    yarn; \
    yarn webpack

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# GTT Base
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
FROM ruby:3.1-slim-bullseye as base

# explicitly set uid/gid to guarantee that it won't change in the future
# the values 999:999 are identical to the current user/group id assigned
RUN groupadd -r -g 999 redmine && useradd -r -g redmine -u 999 redmine

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		wget \
		\
# we need "gsfonts" for generating PNGs of Gantt charts
# and "ghostscript" for creating PDF thumbnails (in 4.1+)
		ghostscript \
		gsfonts \
		imagemagick \
# grab gosu for easy step-down from root
		gosu \
# grab tini for signal processing and zombie killing
		tini \
	; \
# allow imagemagick to use ghostscript for PDF -> PNG thumbnail conversion (4.1+)
	sed -ri 's/(rights)="none" (pattern="PDF")/\1="read" \2/' /etc/ImageMagick-6/policy.xml; \
	rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV production
WORKDIR /usr/src/redmine

# https://github.com/docker-library/redmine/issues/138#issuecomment-438834176
# (bundler needs this for running as an arbitrary user)
ENV HOME /home/redmine
RUN set -eux; \
	[ ! -d "$HOME" ]; \
	mkdir -p "$HOME"; \
	chown redmine:redmine "$HOME"; \
	chmod 1777 "$HOME"

# Defined in docker-compose.yml
ARG REDMINE_VERSION
ARG REDMINE_DOWNLOAD_SHA256

RUN set -eux; \
  # bullseye hack
	wget --no-check-certificate -O redmine.tar.gz "https://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz"; \
	echo "${REDMINE_DOWNLOAD_SHA256} *redmine.tar.gz" | sha256sum -c -; \
	tar -xf redmine.tar.gz --strip-components=1; \
	rm redmine.tar.gz files/delete.me log/delete.me; \
	mkdir -p log public/plugin_assets tmp/pdf tmp/pids; \
	chown -R redmine:redmine ./ ; \
  chmod -R ugo=rwX config ; \
  find log tmp -type d -exec chmod 1777 '{}' +

COPY --from=gtt-builder --chown=redmine:redmine /app/ ./plugins/

COPY --chown=redmine:redmine config/ ./config/

COPY --chown=redmine:redmine Gemfile.local ./

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		gcc \
		libpq-dev \
		libgeos-dev \
		make \
		patch \
	; \
	rm -rf /var/lib/apt/lists/*; \
	\
	gosu redmine bundle config --local without 'development test'; \
	gosu redmine bundle install --jobs "$(nproc)"; \
# fix permissions for running as an arbitrary user
	chmod -R ugo=rwX Gemfile.lock "$GEM_HOME"; \
	rm -rf ~redmine/.bundle; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	find /usr/local -type f -executable -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| grep -v '^/usr/local/' \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual \
	; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false

COPY --chown=redmine:redmine docker-entrypoint.sh /

EXPOSE 3000

ENTRYPOINT [ "/docker-entrypoint.sh" ]

CMD [ "rails", "s", "-b", "0.0.0.0" ]
