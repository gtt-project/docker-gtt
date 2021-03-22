# Hyakumori Dockerized GTT

Docker image and docker-compose file for the Hyakumori GTT Project

This will launch Redmine with the following plugins:

* redmine_text_blocks
* redmine_gtt
* redmine_gtt_smash
* redmine_theme_farend_bleuclair
* redmine_gtt_print
* redmica_s3

## Requirements

- docker-compose

## Quick start

After cloning this repository run:

```
git submodule update --init
cp .env.example .env
docker-compose up --build
```

Open the application on http://localhost:3000/

Default user is `admin/admin`.

## How to use GTT:

Find more information [how to get started with the GTT plugin](https://github.com/gtt-project/redmine_gtt#how-to-use).
