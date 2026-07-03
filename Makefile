COMPOSE ?= docker compose
MIGRATE ?= migrate

.PHONY: up-test up-staging up-prod migrate-up-test migrate-up-staging migrate-up-prod migrate-force-staging run-test run-staging build-prod test test-go test-flutter proto-dart

test: test-go test-flutter

test-go:
	go vet ./...
	go test ./...

test-flutter: proto-dart
	cd frontend && flutter analyze --no-fatal-infos && flutter test

proto-dart:
	mkdir -p frontend/lib/data/generated
	PATH="$$PATH:$$HOME/.pub-cache/bin" protoc --dart_out=grpc:frontend/lib/data/generated -I models models/*.proto

up-test:
	BUS_ENV_FILE=env/test.env $(COMPOSE) --env-file env/test.env -f docker-compose.yaml -f docker-compose.test.yaml up -d --build postgres redis router functions

up-staging:
	BUS_ENV_FILE=env/staging.env $(COMPOSE) --env-file env/staging.env -f docker-compose.yaml -f docker-compose.staging.yaml up -d --build

up-prod:
	BUS_ENV_FILE=env/prod.env $(COMPOSE) --env-file env/prod.env -f docker-compose.yaml -f docker-compose.prod.yaml up -d --build

migrate-up-test:
	$(MIGRATE) -path migrations -database "$${DATABASE_URL:-postgres://bus:bus@localhost:5432/bus_test?sslmode=disable}" up

migrate-up-staging:
	$(MIGRATE) -path migrations -database "$${DATABASE_URL:?DATABASE_URL is required}" up

migrate-up-prod:
	$(MIGRATE) -path migrations -database "$${DATABASE_URL:?DATABASE_URL is required}" up

migrate-force-staging:
	$(MIGRATE) -path migrations -database "$${DATABASE_URL:?DATABASE_URL is required}" force "$${VERSION:?VERSION is required}"

run-test:
	cd frontend && flutter run --dart-define-from-file=env/test.json

run-staging:
	cd frontend && flutter run --dart-define-from-file=env/staging.json

build-prod:
	cd frontend && flutter build ipa --dart-define-from-file=env/prod.json
