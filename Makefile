COMPOSE ?= docker compose --project-directory .
MIGRATE ?= migrate

# Pinned protoc plugin versions. protoc-gen-go tracks the google.golang.org/protobuf
# version in go.mod; protoc-gen-go-grpc is versioned independently. Bump both
# deliberately, never via @latest, so `make proto-go` is reproducible from a
# clean checkout.
PROTOC_GEN_GO_VERSION := v1.36.11
PROTOC_GEN_GO_GRPC_VERSION := v1.6.2
TOOLS_BIN := $(CURDIR)/.tools/bin

# One compose invocation per environment, shared by up-/logs-/down-. Keeping
# the project name, env file, and overlay list in one place stops the three
# targets of an environment from drifting apart.
COMPOSE_TEST := ENV_FILE=env/test.env $(COMPOSE) -p test --env-file ./env/test.env -f docker/docker-compose.yaml -f docker/docker-compose.test.yaml
COMPOSE_STAGING := ENV_FILE=env/staging.env $(COMPOSE) -p staging --env-file ./env/staging.env -f docker/docker-compose.yaml -f docker/docker-compose.staging.yaml
COMPOSE_PROD := ENV_FILE=env/prod.env $(COMPOSE) -p prod --env-file ./env/prod.env -f docker/docker-compose.yaml -f docker/docker-compose.prod.yaml

# Optional service filter for the logs- targets: `make logs-prod SERVICE=router`.
# Empty (the default) follows every service in the environment.
SERVICE ?=

.PHONY: up-test up-staging up-prod up-ollama logs-test logs-staging logs-prod down-test down-staging down-prod migrate-up-test migrate-up-staging migrate-up-prod migrate-force-staging run-test run-staging build-prod test test-go test-flutter proto-go proto-dart verify

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

# verify runs the full hermetic gate: vet + race tests, fatal-on-error/warning
# Flutter analysis + tests, the asset/action/permissions/DB-coverage checks in
# scripts/check-hermetic.sh, the Task 5/6 compose policy checks, the
# engineering-contract gates (dependency boundaries, file-size ratchet, buf
# proto contract, gitleaks, govulncheck, guardrail-test presence — all tools
# pinned, installed into .tools/bin), and a clean git diff after code
# generation (proves generation never mutates tracked source). Flutter's
# asset gate is expected to WARN on a machine without app/assets provisioned
# (gitignored, user-owned) — see check-hermetic.sh.
verify: proto-go
	go vet ./...
	go test -race ./...
	cd app && PATH="$$PATH:$$HOME/.pub-cache/bin" flutter analyze --no-fatal-infos
	cd app && flutter test
	./scripts/check-hermetic.sh
	./scripts/check-compose-isolation.sh
	./scripts/check-container-hardening.sh
	./scripts/check-dependency-boundaries.sh
	./scripts/check-file-budgets.sh
	./scripts/check-proto-contract.sh
	./scripts/check-gitleaks.sh
	./scripts/check-govulncheck.sh
	./scripts/check-guardrail-tests-present.sh
	git diff --exit-code

up-test:
	$(COMPOSE_TEST) up -d --build postgres redis router functions

up-staging:
	$(COMPOSE_STAGING) up -d --build

up-prod:
	$(COMPOSE_PROD) up -d --build

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

migrate-up-test:
	$(MIGRATE) -path migrations -database "$${DATABASE_URL:-postgres://bus:bus@localhost:5432/bus_test?sslmode=disable}" up

migrate-up-staging:
	$(MIGRATE) -path migrations -database "$${DATABASE_URL:?DATABASE_URL is required}" up

migrate-up-prod:
	$(MIGRATE) -path migrations -database "$${DATABASE_URL:?DATABASE_URL is required}" up

migrate-force-staging:
	$(MIGRATE) -path migrations -database "$${DATABASE_URL:?DATABASE_URL is required}" force "$${VERSION:?VERSION is required}"

run-test:
	cd app && flutter run --dart-define-from-file=env/test.json

run-staging:
	cd app && flutter run --dart-define-from-file=env/staging.json

build-prod:
	cd app && flutter build ipa --dart-define-from-file=env/prod.json
