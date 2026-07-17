COMPOSE ?= docker compose --project-directory .

# Pinned protoc plugin versions. protoc-gen-go tracks the google.golang.org/protobuf
# version in go.mod; protoc-gen-go-grpc is versioned independently. Bump both
# deliberately, never via @latest, so `make proto-go` is reproducible from a
# clean checkout.
PROTOC_GEN_GO_VERSION := v1.36.11
PROTOC_GEN_GO_GRPC_VERSION := v1.6.2
TOOLS_BIN := $(CURDIR)/.tools/bin

# each service reads only its own rendered env file (scripts/render-env.sh,
# allowlisted by scripts/env-allowlists/*.txt), not the operator's single
# env/<env>.env — see docs/config.md. The operator contract is unchanged
# (still one env/<env>.env to fill in); render-env-% regenerates
# env/.rendered/<env>/*.env from it before every up-%.
RENDERED_TEST := env/.rendered/test
RENDERED_STAGING := env/.rendered/staging
RENDERED_PROD := env/.rendered/prod

# One compose invocation per environment, shared by up-/logs-/down-. Keeping
# the project name, env file, and overlay list in one place stops the three
# targets of an environment from drifting apart. ENV_FILE stays set (compose-
# level ${BIND_HOST:-...} etc. substitution, and the default env_file: for
# any service that doesn't set its own ENV_FILE_<SERVICE> override) alongside
# the per-service ENV_FILE_<SERVICE> overrides.
COMPOSE_TEST := ENV_FILE=env/test.env \
	ENV_FILE_ROUTER=$(RENDERED_TEST)/router.env ENV_FILE_FUNCTIONS=$(RENDERED_TEST)/functions.env \
	ENV_FILE_INGESTOR=$(RENDERED_TEST)/ingestor.env ENV_FILE_LOADER=$(RENDERED_TEST)/loader.env \
	ENV_FILE_POWERSYNC=$(RENDERED_TEST)/powersync.env \
	$(COMPOSE) -p test --env-file ./env/test.env -f docker/docker-compose.yaml -f docker/docker-compose.test.yaml
COMPOSE_STAGING := ENV_FILE=env/staging.env \
	ENV_FILE_ROUTER=$(RENDERED_STAGING)/router.env ENV_FILE_FUNCTIONS=$(RENDERED_STAGING)/functions.env \
	ENV_FILE_INGESTOR=$(RENDERED_STAGING)/ingestor.env ENV_FILE_LOADER=$(RENDERED_STAGING)/loader.env \
	ENV_FILE_POWERSYNC=$(RENDERED_STAGING)/powersync.env \
	$(COMPOSE) -p staging --env-file ./env/staging.env -f docker/docker-compose.yaml -f docker/docker-compose.staging.yaml
COMPOSE_PROD := ENV_FILE=env/prod.env \
	ENV_FILE_ROUTER=$(RENDERED_PROD)/router.env ENV_FILE_FUNCTIONS=$(RENDERED_PROD)/functions.env \
	ENV_FILE_INGESTOR=$(RENDERED_PROD)/ingestor.env ENV_FILE_LOADER=$(RENDERED_PROD)/loader.env \
	ENV_FILE_POWERSYNC=$(RENDERED_PROD)/powersync.env \
	$(COMPOSE) -p prod --env-file ./env/prod.env -f docker/docker-compose.yaml -f docker/docker-compose.prod.yaml

# Optional service filter for the logs- targets: `make logs-prod SERVICE=router`.
# Empty (the default) follows every service in the environment.
SERVICE ?=

.PHONY: up-test up-staging up-prod up-ollama logs-test logs-staging logs-prod down-test down-staging down-prod migrations-check run-test run-staging build-prod test test-go test-flutter proto-go proto-dart verify render-env-test render-env-staging render-env-prod

test: test-go test-flutter

test-go: proto-go
	go vet ./...
	go test ./...

test-flutter: proto-dart
	cd app && flutter analyze --no-fatal-infos && flutter test

proto-go:
	mkdir -p $(TOOLS_BIN)
	GOBIN=$(TOOLS_BIN) go install google.golang.org/protobuf/cmd/protoc-gen-go@$(PROTOC_GEN_GO_VERSION)
	GOBIN=$(TOOLS_BIN) go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@$(PROTOC_GEN_GO_GRPC_VERSION)
	PATH="$(TOOLS_BIN):$$PATH" protoc --go_out=paths=source_relative:models --go-grpc_out=paths=source_relative:models -I models models/*.proto

proto-dart:
	mkdir -p app/lib/data/generated
	PATH="$$PATH:$$HOME/.pub-cache/bin" protoc --dart_out=grpc:app/lib/data/generated -I models models/*.proto

verify: proto-go
	./scripts/ci.sh contracts
	./scripts/ci.sh go
	./scripts/ci.sh flutter
	./scripts/ci.sh security
	./scripts/ci.sh migrations
	./scripts/check-hermetic.sh
	./scripts/check-compose-isolation.sh
	./scripts/check-container-hardening.sh
	git diff --exit-code

render-env-test:
	./scripts/render-env.sh env/test.env $(RENDERED_TEST)

render-env-staging:
	./scripts/render-env.sh env/staging.env $(RENDERED_STAGING)

render-env-prod:
	./scripts/render-env.sh env/prod.env $(RENDERED_PROD)

up-test: render-env-test
	$(COMPOSE_TEST) up -d --build postgres redis router functions

up-staging: render-env-staging
	$(COMPOSE_STAGING) up -d --build --wait

up-prod: render-env-prod
	$(COMPOSE_PROD) up -d --build --wait

# logs- follows (Ctrl-C to stop) and starts from the last 200 lines, enough to
# catch the failure that prompted the call without replaying the whole history.
logs-test:
	$(COMPOSE_TEST) logs -f --tail=200 $(SERVICE)

logs-staging:
	$(COMPOSE_STAGING) logs -f --tail=200 $(SERVICE)

logs-prod:
	$(COMPOSE_PROD) logs -f --tail=200 $(SERVICE)

# down stops and removes containers, never volumes -- prod's ./osrm-data and the
# test postgres survive a down/up cycle.
down-test:
	$(COMPOSE_TEST) down

down-staging:
	$(COMPOSE_STAGING) down

down-prod:
	$(COMPOSE_PROD) down

up-ollama:
	$(COMPOSE) -p dev -f docker/docker-compose.yaml --profile gpu up -d --build ollama

migrations-check:
	./scripts/check-migrations.sh

run-test:
	cd app && flutter run --dart-define-from-file=env/test.json

run-staging:
	cd app && flutter run --dart-define-from-file=env/staging.json

build-prod:
	cd app && flutter build ipa --dart-define-from-file=env/prod.json
