FROM redmine:4.1

RUN apt-get update \
 && apt-get install -y \
        git \
        perl \
        wget \
 && git submodule update --recursive \
 && apt-get purge -y \
        git \
        perl \
        wget \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*
