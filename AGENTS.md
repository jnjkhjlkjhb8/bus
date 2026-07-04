# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, etc.) working in this repository. `CLAUDE.md` imports this file.

## Before changing code

- Read `docs/README.md` for the doc index and `CONTEXT.md` for domain language.
- When instructions are unclear, ask first. Design/spec before code for non-trivial features.

## Commands

### Tests (one command, from repo root)

```bash
make test          # go vet + go test + proto gen + flutter analyze + flutter test
make test-go       # backend only
make test-flutter  # frontend only (regenerates Dart proto stubs first)
```

DB-dependent Go tests skip themselves when `DATABASE_URL` is unset. `flutter analyze` gates on errors/warnings (`--no-fatal-infos`); don't introduce new info-level lints.

### Backend (Go)

```bash
go run ./services/router       # gRPC server (local dev)
go run ./services/functions    # ingestion scheduler (local dev)
go test ./...                  # all backend tests
go test ./services/router/...  # one package
```

### Frontend (Flutter)

```bash
cd app
make -C .. run-test          # flutter run with test flavor (recommended)
flutter run --dart-define-from-file=env/test.json   # equivalent
flutter test
flutter analyze
```

Flavor config lives in `app/env/{test,staging,prod}.json` (`API_BASE_URL`, `POWERSYNC_URL`, `GRPC_HOST/PORT/TLS`, `FIREBASE_ENABLED`, `APP_ENV`). Never pass individual `--dart-define` flags; edit the flavor file instead.

### Protobuf / gRPC code generation

**Rule: only edit `models/*.proto`. Never manually edit generated files.**

- `models/*.pb.go` — generated inside Docker at build time; gitignored
- `app/lib/data/generated/*.dart` — generated locally; gitignored

When a `.proto` changes, regenerate Dart stubs from repo root:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
protoc --dart_out=grpc:app/lib/data/generated -I models models/*.proto
```

Go stubs rebuild automatically on the next `docker compose up --build`. Proto changes are wire-breaking: backend and app must ship together.

### Database migrations

SQL migrations live in `migrations/` (single source; hand-applied). New DDL = new dated file there. The user applies them to Azure with `psql "$DATABASE_URL" -f migrations/<file>.sql` — agents cannot reach the database directly. Write conventions for ingestion SQL are documented in `docs/storage.md`.

## Environments & deployment

Three environments, selected by compose overrides + env files:

| Env | Compose | Env file | Database |
|---|---|---|---|
| test | `docker-compose.test.yaml` | `env/test.env` | local `postgres` service (in compose) |
| staging | `docker-compose.staging.yaml` | `env/staging.env` | Azure, `PG_SCHEMA=staging` |
| prod | `docker-compose.prod.yaml` | `env/prod.env` | Azure, `public` schema |

```bash
make up-test      # local stack: postgres + redis + router + functions
make up-staging   # full stack, staging env
make up-prod      # full stack, prod env

docker compose restart <service>
docker compose logs -f <service>
```

Copy `env/<env>.env.example` to `env/<env>.env` and fill values. Real env files are gitignored — never commit secrets.

**CI/CD** (`.github/workflows/`): `ci.yaml` runs Go tests (with postgres+redis services) and Flutter analyze/test on PRs and main. `deploy-staging.yaml` SSH-deploys on push to main (`make up-staging`). `deploy-prod.yaml` deploys on manual approval via the `production` GitHub environment.

### Key environment variables

Full reference: `docs/config.md` and `env/*.env.example`.

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string |
| `PG_SCHEMA` | Schema override (staging isolation) |
| `REDIS_ADDR` | `redis:6379` (Docker internal — do not change) |
| `TDX_CLIENT_ID` / `TDX_CLIENT_SECRET` | TDX API credentials (prod ingestor only; other envs load from `raw_tdx` and may leave them empty) |
| `CWA_API_KEY` | Weather data (bus ETA prediction) |
| `HF_TOKEN` | HuggingFace embedding fallback |
| `OSRM_FILE` | Pre-processed `.osrm` file in `osrm-data/` |
| `MQTT_*` | TDX MQTT credentials (empty = skip) |
| `SENTRY_DSN` / `SENTRY_ENVIRONMENT` | Error tracking (empty DSN = no-op) |
| `ROUTER_DB_MAX_CONNS` etc. | Connection pool overrides (Azure cap: 50 total) |
| `*_MEM_LIMIT` / `*_GOMEMLIMIT` | Per-service memory tuning |

## Architecture

### Deployment — single Ubuntu host (6 GB RAM)

Services in `docker-compose.yaml`:

| Service | Image | Port(s) | Notes |
|---|---|---|---|
| ollama | ollama | 127.0.0.1:11434 | Embeddings; `gpu` profile, optional |
| redis | redis:7-alpine | 127.0.0.1:6379 | ETA cache + Pub/Sub |
| router | bus-router | 50051 (gRPC), 8080 (HTTP) | Request path |
| functions | bus-functions | — | Realtime ETA + MQTT + 03:30 raw_tdx load (empty `ROLE`) |
| ingestor | bus-functions | — | 03:00 raw TDX landing into shared `raw_tdx` (`ROLE=ingestor`; runs in every env but only prod holds TDX credentials — no-op elsewhere) |
| powersync | journeyapps/powersync-service | 8081 | Offline sync |
| osrm | osrm/osrm-backend | 127.0.0.1:5000 | Routing engine |

PostgreSQL is on **Azure** (external). `functions` and `ingestor` share one image, differentiated by `ROLE`.

### Backend — two Go binaries

**`services/functions/`** — ingestion scheduler + TDX MQTT subscriber. `robfig/cron`:

| Schedule | Job |
|---|---|
| 03:00 daily | raw TDX landing into shared `raw_tdx` (`ROLE=ingestor`; TDX credentials prod-only, no-op elsewhere) |
| 03:30 daily | load: `raw_tdx` → this env's `PG_SCHEMA` (every env's functions; no TDX calls) |
| 03:45 daily | `changetovector` (vector update, after the load) |
| 04:00 daily | `computeTravelAvg` (ETA prediction) |
| 04:30 daily | `cleanupBusHistory` (30-day retention) |
| every 10 s | `mrtEta` |
| every 30 s | `bikeEta`, `busEta` (+ notification dispatch) |
| every 2 min | `traEta` |
| every 10 min | `weatherSync` |

MQTT (`mqtt.go`): subscribes to `mqtt.transportdata.tw:8883`, publishes alerts through Redis Pub/Sub. Bus ETA prediction (schedule + travel averages + XGBoost) fills gaps when TDX has no live ETA.

**`services/router/`** — gRPC on `:50051` + HTTP on `:8080`.
- gRPC: static queries → PostgreSQL; realtime streams → Redis Pub/Sub.
- Rail (TRA/THSR) is a pure read path: a miss (e.g. a date beyond the landed timetable window) returns `NotFound` — the router never fetches TDX on miss (ADR-0005).
- HTTP: `GET /api/token/powersync` (JWT), `GET /api/.well-known/jwks.json`, `POST /api/embed` (embedding proxy).

**`models/*.proto`** — source of truth for the API.

### Data flow

```
TDX REST API ──03:00 (ingestor; TDX creds prod-only)──→ raw_tdx (shared schema)
raw_tdx ──03:30 (each env's functions)──→ PostgreSQL (env PG_SCHEMA static)

TDX REST API ──realtime crons──→ functions ──→ Redis (ETA cache + Pub/Sub)

TDX MQTT ──push──→ functions ──→ Redis (alert cache + Pub/Sub)

Redis Pub/Sub ──→ router ──gRPC stream──→ Flutter

PostgreSQL ──→ PowerSync ──sync──→ Flutter SQLite (offline search)
```

### Frontend (Flutter)

Entry: `app/lib/main.dart`. App name: 我車呢 (`wheres_the_car`).

**Directory structure** (feature-first):
```
lib/
├── app/      → app.dart, router/app_router.dart, theme/app_theme.dart
├── core/     → grpc/, powersync/, storage/hive_store.dart, location/,
│               haptics/, firebase/, http/
├── data/     → generated/ (protoc output), repositories/, decoders/, models/
├── features/ → home bus metro rail bike go search favorites alerts map
│               settings onboarding planner live_activity monitor ui_kit
└── shared/   → widgets/ map/ motion/
```

**Routing**: `go_router` with a single `StatefulShellRoute` branch; shell is `shared/widgets/main_scaffold.dart` (content + floating `NavMiniBar`). Main routes: `/` (home), `/search`, `/favorites`, `/bus/stop`, `/bus/route/:subRouteUid`, `/bike/station`, `/rail`, `/metro`, `/go` (planner), `/settings`, `/ui-kit` (component gallery).

**State management**: `flutter_bloc` Bloc only (no Cubit). Bottom sheets use `smooth_sheets`.

**Search**: full-screen `/search` route driven by `SearchBloc`; queries the PowerSync SQLite `search_vector` table (offline-capable).

**Alerts**: `AlertBloc` globally provided in `app.dart`, subscribes to alert streams on startup.

**Design system**: `docs/design.md` is the single source for tokens, components, and motion rules. Key invariants: Ink `#111111` is the only UI accent; transit line colors are data, not decoration; all time values in JetBrainsMono; coming-soon highlight is static (never pulsing); respect reduce-motion.

## Docs

Full index: `docs/README.md`. Most used:

| File | Contents |
|---|---|
| `docs/requirements.md` | Feature requirements and active constraints |
| `docs/architecture.md` | System architecture and deployment |
| `docs/grpc.md` | gRPC service specifications |
| `docs/storage.md` | PostgreSQL schema + ingestion SQL conventions |
| `docs/redis.md` | Redis key/channel conventions |
| `docs/design.md` | Design system (tokens, components, motion) |
| `docs/adr/` | Architecture decision records |

## Agent conventions

- **Issues**: GitHub Issues for `jnjkhjlkjhb8/bus`. See `docs/agents/issue-tracker.md`.
- **Triage labels**: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.
- **Domain docs**: `CONTEXT.md` at root + `docs/adr/`. See `docs/agents/domain.md`.
- **Never commit or push without explicit user approval.**
