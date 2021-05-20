FROM ruby:2.6-slim-buster

# explicitly set uid/gid to guarantee that it won't change in the future
# the values 999:999 are identical to the current user/group id assigned
RUN groupadd -r -g 999 redmine && useradd -r -g redmine -u 999 redmine

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		wget \
		\
		# bzr \
		# git \
		# mercurial \
		openssh-client \
		# subversion \
		\
# we need "gsfonts" for generating PNGs of Gantt charts
# and "ghostscript" for creating PDF thumbnails (in 4.1+)
		ghostscript \
		gsfonts \
		imagemagick \
# https://github.com/docker-library/ruby/issues/344
		shared-mime-info \
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

ARG REDMINE_VERSION="4.2.1"
ARG REDMICA_VERSION=""
# ENV REDMINE_DOWNLOAD_SHA256 ad4109c3425f1cfe4c8961f6ae6494c76e20d81ed946caa1e297d9eda13b41b4

RUN set -eux; \
	if [ -n "$REDMINE_VERSION" ]; then \
		wget -O redmine.tar.gz "https://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz"; \
		# echo "$REDMINE_DOWNLOAD_SHA256 *redmine.tar.gz" | sha256sum -c -;
	elif [ -n "$REDMICA_VERSION" ]; then \
		wget -O redmine.tar.gz "https://github.com/redmica/redmica/archive/v${REDMICA_VERSION}.tar.gz"; \
	fi; \
	tar -xf redmine.tar.gz --strip-components=1; \
	rm redmine.tar.gz files/delete.me log/delete.me; \
	mkdir -p log public/plugin_assets sqlite tmp/pdf tmp/pids; \
	chown -R redmine:redmine ./; \
# log to STDOUT (https://github.com/docker-library/redmine/issues/108)
	echo 'config.logger = Logger.new(STDOUT)' > config/additional_environment.rb; \
# fix permissions for running as an arbitrary user
	chmod -R ugo=rwX config db sqlite; \
	find log tmp -type d -exec chmod 1777 '{}' +

# for Redmine patches
ARG PATCH_STRIP=1
ARG PATCH_DIRS=""
COPY patches/ ./patches/

# for GTT gem native extensions
ARG GEM_PG_VERSION="1.1.4"
COPY Gemfile.local ./
COPY plugins/ ./plugins/

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		# freetds-dev \
		gcc \
		# libmariadbclient-dev \
		libpq-dev \
		# libsqlite3-dev \
		make \
		patch \
# in 4.1+, libmagickcore-dev and libmagickwand-dev are no longer necessary/used: https://www.redmine.org/issues/30492
		libmagickcore-dev libmagickwand-dev \
# for GTT dependencies
		g++ \
		libgeos-dev \
		curl \
	; \
	rm -rf /var/lib/apt/lists/*; \
	\
	if [ -n "$PATCH_DIRS" ]; then \
		for dir in $(echo $PATCH_DIRS | sed "s/,/ /g"); do \
			for file in ./patches/"$dir"/*; do \
				patch -p"$PATCH_STRIP" < $file; \
			done; \
		done; \
		rm -rf ./patches/*; \
	fi; \
	curl -sL https://deb.nodesource.com/setup_14.x | bash -; \
	apt-get install -y --no-install-recommends nodejs; \
	curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -; \
	echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list; \
	apt-get update; \
	apt-get install -y --no-install-recommends yarn; \
	for plugin in ./plugins/*; do \
		if [ -f "$plugin/webpack.config.js" ]; then \
			cd "$plugin" && yarn && npx webpack && cd ../..; \
		fi; \
	done; \
	export GEM_PG_VERSION="$GEM_PG_VERSION"; \
	gosu redmine bundle config --local without 'development test'; \
# fill up "database.yml" with bogus entries so the redmine Gemfile will pre-install all database adapter dependencies
# https://github.com/redmine/redmine/blob/e9f9767089a4e3efbd73c35fc55c5c7eb85dd7d3/Gemfile#L50-L79
	echo '# the following entries only exist to force `bundle install` to pre-install all database adapter dependencies -- they can be safely removed/ignored' > ./config/database.yml; \
	# for adapter in mysql2 postgresql sqlserver sqlite3; do \
	for adapter in postgis; do \
		echo "$adapter:" >> ./config/database.yml; \
		echo "  adapter: $adapter" >> ./config/database.yml; \
	done; \
	gosu redmine bundle install --jobs "$(nproc)"; \
	rm ./config/database.yml; \
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

COPY config/ ./config/
VOLUME /usr/src/redmine/files

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 3000
CMD ["rails", "server", "-b", "0.0.0.0"]
