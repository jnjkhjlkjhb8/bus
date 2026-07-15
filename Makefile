COMPOSE ?= docker compose --project-directory .
MIGRATE ?= migrate

# Pinned protoc plugin versions. protoc-gen-go tracks the google.golang.org/protobuf
# version in go.mod; protoc-gen-go-grpc is versioned independently. Bump both
# deliberately, never via @latest, so `make proto-go` is reproducible from a
# clean checkout.
PROTOC_GEN_GO_VERSION := v1.36.11
PROTOC_GEN_GO_GRPC_VERSION := v1.6.2
TOOLS_BIN := $(CURDIR)/.tools/bin

.PHONY: up-test up-staging up-prod up-ollama migrate-up-test migrate-up-staging migrate-up-prod migrate-force-staging run-test run-staging build-prod test test-go test-flutter proto-go proto-dart verify

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
# scripts/check-hermetic.sh, the Task 5/6 compose policy checks, and a clean
# git diff after code generation (proves generation never mutates tracked
# source). Flutter's asset gate is expected to WARN on a machine without
# app/assets provisioned (gitignored, user-owned) — see check-hermetic.sh.
verify: proto-go
	go vet ./...
	go test -race ./...
	cd app && PATH="$$PATH:$$HOME/.pub-cache/bin" flutter analyze --no-fatal-infos
	cd app && flutter test
	./scripts/check-hermetic.sh
	./scripts/check-compose-isolation.sh
	./scripts/check-container-hardening.sh
	git diff --exit-code

up-test:
	BUS_ENV_FILE=env/test.env $(COMPOSE) -p bus-test --env-file ./env/test.env -f docker/docker-compose.yaml -f docker/docker-compose.test.yaml up -d --build postgres redis router functions

up-staging:
	BUS_ENV_FILE=env/staging.env $(COMPOSE) -p bus-staging --env-file ./env/staging.env -f docker/docker-compose.yaml -f docker/docker-compose.staging.yaml up -d --build

up-prod:
	BUS_ENV_FILE=env/prod.env $(COMPOSE) -p bus-prod --env-file ./env/prod.env -f docker/docker-compose.yaml -f docker/docker-compose.prod.yaml up -d --build

up-ollama:
	$(COMPOSE) -p bus-dev -f docker/docker-compose.yaml --profile gpu up -d --build ollama

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
