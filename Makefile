COMPOSE ?= docker compose --project-directory .
MIGRATE ?= migrate

.PHONY: up-test up-staging up-prod up-ollama migrate-up-test migrate-up-staging migrate-up-prod migrate-force-staging run-test run-staging build-prod test test-go test-flutter proto-dart

test: test-go test-flutter

test-go:
	go vet ./...
	go test ./...

test-flutter: proto-dart
	cd app && flutter analyze --no-fatal-infos && flutter test

proto-dart:
	mkdir -p app/lib/data/generated
	PATH="$$PATH:$$HOME/.pub-cache/bin" protoc --dart_out=grpc:app/lib/data/generated -I models models/*.proto

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
