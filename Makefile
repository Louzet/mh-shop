#!make


-include .env
export

## If you want to run a comand for the prod environment,
## Simply replace value of ENV variable in '.env' file

## dev is the default environment, it use the docker-compose.yml file
## prod use the docker-compose-prod.yml file
ENV ?= dev

ifeq ($(ENV),prod)
CONFIG = docker-compose-prod.yml
else
CONFIG = docker-compose.yml
endif

DOCKER_COMPOSE = docker-compose -f $(CONFIG)
SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
EXEC_PHP        = $(DOCKER_COMPOSE) exec -T php
SYMFONY = $(EXEC_PHP) bin/console

# Create configuration files needed by the environment
SETUP_ENV := $(shell (test -f $(SELF_DIR).env || cp $(SELF_DIR).env.dist $(SELF_DIR).env))
SETUP_SERVER := $(shell (test -f $(SELF_DIR)docker/nginx/conf.d/default.conf || cp $(SELF_DIR)docker/nginx/conf.d/default.conf.dist $(SELF_DIR)docker/nginx/conf.d/default.conf))


##
## ----------------------------------------------------------------------------
##   Environment
## ----------------------------------------------------------------------------
##

restore: ## Restore the "postgres" volume
	docker run --rm \
		--volumes-from $$(docker-compose ps -q postgres) \
		-v $$(pwd):/backup \
		busybox sh -c "tar xvf /backup/backup.tar /var/lib/postgresql/data"
	docker-compose restart postgres

install: ## Install and start the project

build:
	$(DOCKER_COMPOSE) pull --parallel --quiet --ignore-pull-failures 2> /dev/null
	$(DOCKER_COMPOSE) build --pull

install: build start vendor

## Start the environment
start:
	@echo 'Starting containers in [$(ENV)] mode'
	$(DOCKER_COMPOSE) up -d

stats: ## Print real-time statistics about containers ressources usage
	docker stats $(docker ps --format={{.Names}})

stop: ## Stop the environment
	$(DOCKER_COMPOSE) stop

kill:
	$(DOCKER_COMPOSE) kill
	$(DOCKER_COMPOSE) down --volumes --remove-orphans
	sudo rm -rf logs/*

reset: kill install

vendor: composer.lock
	$(COMPOSER) install

backup: ## Backup the "postgres" volume
	docker run --rm \
		--volumes-from $$(docker-compose ps -q postgres) \
		-v $$(pwd):/backup \
		busybox sh -c "tar cvf /backup/backup.tar /var/lib/postgresql/data"

composer: ## Install Composer dependencies from the "php" container
	$(EXEC_PHP) "composer install --optimize-autoloader --prefer-dist"

logs: ## Follow logs generated by all containers
	@echo 'Log containers in [$(ENV)] mode'
	$(DOCKER_COMPOSE) logs -f --tail=0

logs-full: ## Follow logs generated by all containers from the containers creation
	@echo 'Log containers in [$(ENV)] mode'
	$(DOCKER_COMPOSE) logs -f

nginx: ## Open a terminal in the "nginx" container
	$(DOCKER_COMPOSE) exec nginx sh

.PHONY: php
php: ## Open a terminal in the "php" container
	$(DOCKER_COMPOSE) exec php sh

ps: ## List all containers managed by the environment
	$(DOCKER_COMPOSE) ps

# default args for psql
user = root
db = mh-shop
psql: ## launch an psql on docker postgres
	$(DOCKER_COMPOSE) exec db psql -U $(user) -d $(db)

##
## ----------------------------------------------------------------------------
##   Symfony
## ----------------------------------------------------------------------------
##
.PHONY: db_install
db_install:
	$(EXEC_PHP) bin/console doctrine:database:create
	$(EXEC_PHP) bin/console doctrine:schema:update

cache: ## Flush the Symfony cache
	$(SYMFONY) cache:clear

db_drop:
	$(SYMFONY) doctrine:database:drop --force

migrate:
	$(SYMFONY) doctrine:migrations:migrate

migration:
	$(SYMFONY) make:migration

fixtures:
	$(SYMFONY) doctrine:fixtures:load

phpunit:
	./vendor/bin/phpunit

.PHONY: db_drop migration migrate fixtures

.PHONY: backup build cache composer logs logs-full nginx php ps restore start stats stop

.DEFAULT_GOAL := help
help:
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) \
		| sed -e 's/^.*Makefile://g' \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' \
		| sed -e 's/\[32m##/[33m/'
.PHONY: help
