# Week 7 — Advanced Docker Practices

This document covers:

- Task 1: Docker image optimization.
- Task 2: a local Django and PostgreSQL environment with automatic migrations.
- Task 3: a reproducible multi-container demonstration of bridge,
  host, and overlay networking.

The networking demonstration passed for all three types.
Overlay was tested on a single Docker host; cross-host traffic
was not tested.

## Files to review

| File | Purpose |
| --- | --- |
| Dockerfile.single | Single-stage comparison build. Build tools remain in the final image. |
| Dockerfile.multistage | Multi-stage comparison build. Separates compilation from runtime components. |
| Dockerfile | Main application build used by Compose, including the final caching improvements. |
| .dockerignore | Excludes unnecessary files and local secrets from the build context. |
| requirements.txt | Python dependencies installed during the build. |
| docker-compose.yaml | Django, PostgreSQL, automatic migrations, and persistent storage. |
| docker-compose.networking.yaml | Three server/client pairs demonstrating bridge, host, and overlay. |
| evidence/task1-final-image.txt | Recorded size of the main application image. |
| evidence/task3-networking/containers.txt | Networking demonstration container statuses. |
| evidence/task3-networking/results.txt | DNS and HTTP results for all three networking types. |
| evidence/task3-networking/networks.txt | Recorded network drivers and scopes. |

## Task 1 — Docker Image Optimization

### Comparison files

Start by comparing Dockerfile.single with Dockerfile.multistage.

Dockerfile.single builds the application in one stage.
Compilation tools and runtime components remain in the final image.

Dockerfile.multistage separates the build into stages.
The builder prepares dependencies and application assets.
The runtime stage receives the application and required runtime
components without the build toolchain.

The image tags healthchecks:single and healthchecks:multi identify
these comparison builds.

Then review Dockerfile, which is the main build used by Compose.
It includes the final caching and permission-processing improvements.

### Main Dockerfile design

The main Dockerfile has two stages:

- builder: installs compilation tools, verifies and builds curl,
  installs Python dependencies, and prepares static assets.
- runtime: contains the application, Python dependencies,
  selected curl files, and required runtime libraries.

The application runs as user app with UID 10001.
Build tools are not copied into the runtime stage.

### Improvements

- Added Gunicorn to requirements.txt to match the startup command.
- Declared the final Django and PyJWT versions in requirements.txt,
  removing a second installation that replaced earlier versions.
- Installed dependencies before copying application source.
- Added a BuildKit cache mount for pip without including its package
  cache in the image layers.
- Separated dependency permission processing from application files
  to improve caching when only source changes.
- Used .dockerignore to exclude secrets, local environments,
  infrastructure files, evidence, and comparison Dockerfiles.

CHANGELOG.md must remain in the build context because hc/settings.py
reads it during initialization.

### Single-stage versus multi-stage sizes

The comparison used the same application source, Python base image,
requirements, and linux/arm64 architecture.

| Comparison image | Size in bytes | Decimal MB | GCC |
| --- | ---: | ---: | --- |
| healthchecks:single | 856196937 | 856.20 | Available |
| healthchecks:multi | 373737475 | 373.74 | Absent |

The multi-stage comparison image was 482459462 bytes smaller:
a reduction of 56.35% relative to the single-stage comparison image.

These are recorded experiment results, not newly measured sizes
of the current main Dockerfile.

Week 6 already used a multi-stage build. This percentage demonstrates
the difference from the single-stage alternative, not an improvement
of 56.35% over Week 6.

Both comparison images passed:

- Django WSGI initialization.
- Gunicorn and PycURL imports.
- PostgreSQL connection through Django.

These checks do not cover every application feature.

### Build measurements

| Recorded scenario | Time |
| --- | ---: |
| Build with Docker layer cache disabled | 159.81 seconds |
| Rebuild using Docker layer cache | 12.15 seconds |

BuildKit cache mounts can retain data even with --no-cache.
These measurements describe different cache conditions and do not
isolate a speed improvement over the original Dockerfile.

The main Dockerfile subsequently received a permission-step
ordering change. Its final recorded size is stored separately
in evidence/task1-final-image.txt.

### Reproduce the comparison

Build the single-stage image:

```bash
docker build --platform linux/arm64 \
  -f Dockerfile.single -t healthchecks:single .
```

Build the multi-stage comparison image:

```bash
docker build --platform linux/arm64 \
  -f Dockerfile.multistage -t healthchecks:multi .
```

Compare sizes:

```bash
docker image inspect healthchecks:single healthchecks:multi \
  --format 'TAGS={{json .RepoTags}} SIZE_BYTES={{.Size}}'
```

Build the main application image:

```bash
docker build --platform linux/arm64 \
  -f Dockerfile -t healthchecks:week7-task1 .
```

Later rebuilds may produce different sizes if base images
or downloaded system packages change.

Multi-stage builds reduce distributed image contents.
They do not inherently make Python execute faster.
Intermediate build results can still occupy local builder cache.

## Task 2 — Docker Compose for Local Development

### Services and startup order

docker-compose.yaml defines project week7-healthchecks.

| Service | Purpose |
| --- | --- |
| db | PostgreSQL 17 with persistent database storage. |
| migrate | Applies pending Django migrations and exits. |
| web | Runs Django through Gunicorn at http://localhost:8000. |

The migrate and web services use the same image:
healthchecks:week7-task1.

Shared build and environment configuration is declared using
the x-app extension and YAML anchor.

Startup proceeds as follows:

1. PostgreSQL starts and passes its health check.
2. migrate runs python manage.py migrate --noinput.
3. After migrate exits successfully, web starts.

The dependency conditions are service_healthy for PostgreSQL
and service_completed_successfully for the migration job.

Exited (0) is the expected successful status of migrate.
If the migration job fails, the dependency condition prevents
the dependent web service from starting through this startup flow.

### Local configuration

The local .env file must contain independent values for:

```dotenv
DJANGO_SECRET_KEY=
POSTGRES_PASSWORD=
```

Generate each value separately:

```bash
openssl rand -hex 32
```

Restrict access to the existing file:

```bash
chmod 600 .env
```

Compose maps the configuration as follows:

| Local variable | Container variable | Service |
| --- | --- | --- |
| DJANGO_SECRET_KEY | SECRET_KEY | web and migrate |
| POSTGRES_PASSWORD | DB_PASSWORD | web and migrate |
| POSTGRES_PASSWORD | POSTGRES_PASSWORD | db |

Database name hc, username hc, hostname db, and port 5432
are configured directly in docker-compose.yaml.

.env is excluded from Git and the Docker build context.
It is a plaintext local configuration file, not an encrypted store.

### Build and start

Run from the repository root.

Validate the configuration without printing its values:

```bash
docker compose -f docker-compose.yaml config --quiet
```

Build the shared application image:

```bash
docker compose -f docker-compose.yaml build web
```

Start PostgreSQL, run migrations, and start the application:

```bash
docker compose -f docker-compose.yaml up -d --no-build
```

Inspect services and logs:

```bash
docker compose -f docker-compose.yaml ps -a
docker compose -f docker-compose.yaml logs --tail=60 migrate web
```

Open http://localhost:8000.

### How migrations work

Migration files describe database schema changes and sometimes
data transformations.

One migrate command applies all pending migrations in dependency
order. It does not execute only one migration file.

Django records successful migrations in the PostgreSQL table
django_migrations. Previously applied migrations are skipped.

No migrations to apply means that the database already contains
all migration changes available in the current image.

The command runs inside the migrate container, but SQL changes
are executed in PostgreSQL. Database tables, data, and migration
history are stored in the PostgreSQL volume.

Migrations are not executed during docker build.
Building an image does not update a database.

The startup job applies existing migration files.
It does not generate new files with makemigrations.

### Development workflow

Source code is copied into the image.
This setup does not configure a source bind mount or automatic reload.

After changing code, dependencies, or migration files:

```bash
docker compose -f docker-compose.yaml build web
docker compose -f docker-compose.yaml up -d --no-build \
  --force-recreate migrate web
```

This rebuilds the shared image and recreates the migration job
and web service with dependency ordering.

Inspect migration status:

```bash
docker compose -f docker-compose.yaml exec web \
  python manage.py showmigrations
```

- [X] means applied.
- [ ] means pending.

When model changes require new migration files, generate them
and commit them with the corresponding application changes.

### Networking and persistence

Compose creates the user-defined bridge network
week7-healthchecks_default.

Django connects to PostgreSQL using db:5432.
Docker resolves db to the database container's IP.

Only web publishes a host port: 127.0.0.1:8000.
PostgreSQL does not publish a host port.

The db service mounts postgres-data at /var/lib/postgresql/data.
The full volume name is week7-healthchecks_postgres-data.

This volume stores application data and migration history.
Rebuilding images or recreating containers does not reset it.

Inspect storage:

```bash
docker volume inspect week7-healthchecks_postgres-data
```

On macOS, the volume is inside Docker Desktop's Linux VM.

Stop the application while retaining database data:

```bash
docker compose -f docker-compose.yaml down
```

Do not add -v when retaining database data.

Changing POSTGRES_PASSWORD in .env does not update the role password
inside an already initialized PostgreSQL data directory.

### Verified results

- PostgreSQL passed its health check.
- migrate exited with code 0.
- Django connected to PostgreSQL through hostname db.
- SELECT 1 succeeded.
- The migration plan contained zero pending migrations.
- showmigrations listed 205 applied migrations.
- The application returned HTTP 200 after following the login redirect.
- Migration history persisted across container recreation
  while the named volume was retained.

SMTP is not configured; email-dependent features were not validated.

## Task 3 — Docker Networking

### Network differences and use cases

| Type | Behavior | Typical use case |
| --- | --- | --- |
| User-defined bridge | Connects containers on one Docker host. Provides container-name DNS and separation between application networks. | Local development and applications such as Django with PostgreSQL on one host. |
| Host | Uses the host network stack. No separate container network address or port publishing is used. Network isolation is reduced and port conflicts must be managed. | Applications requiring many ports or avoiding bridge port translation. |
| Overlay | Connects containers across Docker hosts participating in a Swarm. Runs over the underlying host network. | Distributed applications and Swarm services across multiple hosts. |

Docker Desktop requires enabling host networking in Settings.
Its host networking implementation supports TCP and UDP and differs
from native Linux host networking.

Overlay requires Swarm mode, including for standalone containers.
attachable: true allows ordinary Compose containers to join it.
Application traffic encryption is optional and was not enabled
in this demonstration.

This comparison can be copied into the Trello ticket.
Posting to Trello is a separate submission step.

### Reproducible multi-container setup

docker-compose.networking.yaml defines project week7-network-demo
with three server/client pairs:

| Pair | Configuration | Client destination |
| --- | --- | --- |
| bridge-server / bridge-client | User-defined bridge network | http://bridge-server:18082/ |
| host-server / host-client | network_mode: host | http://127.0.0.1:18082/ |
| overlay-server / overlay-client | Attachable overlay network | http://overlay-server:18082/ |

All containers reuse healthchecks:week7-task1.
Servers override the image command with Python's HTTP server.
Clients override it with a DNS and HTTP verification script.

Each client waits for its server's health check and exits after
the request. Successful clients exit with code 0.

No ports are published with ports: or -p.
Bridge and overlay clients communicate inside their networks.
The host pair communicates through the shared host network stack.

### Prerequisites

- The healthchecks:week7-task1 image must exist locally.
- Docker Desktop host networking must be enabled.
- Swarm must be active for the overlay network.

Check Swarm state:

```bash
docker info --format 'Swarm={{.Swarm.LocalNodeState}}'
```

If inactive, initialize the local demonstration Swarm:

```bash
docker swarm init
```

### Run the demonstration

Validate and start:

```bash
docker compose -f docker-compose.networking.yaml config --quiet
docker compose -f docker-compose.networking.yaml up -d --no-build
```

Inspect all six containers:

```bash
docker compose -f docker-compose.networking.yaml ps -a
```

Expected: three healthy servers and three clients with Exited (0).

Read client results:

```bash
docker compose -f docker-compose.networking.yaml logs --no-color \
  bridge-client host-client overlay-client
```

Expected:

```text
bridge: PASS
host: PASS
overlay: PASS
```

Inspect network drivers and scopes:

```bash
docker network inspect \
  week7-task3-demo-bridge \
  week7-task3-demo-overlay \
  --format 'Name={{.Name}} Driver={{.Driver}} Scope={{.Scope}}'
```

### Verified results

| Mode | Resolved destination during the test | HTTP | Client exit code |
| --- | --- | ---: | ---: |
| bridge | 172.22.0.2 | 200 | 0 |
| host | 127.0.0.1 | 200 | 0 |
| overlay | 10.0.1.2 | 200 | 0 |

The bridge network reported Driver=bridge and Scope=local.
The overlay network reported Driver=overlay and Scope=swarm.

Container IP addresses are dynamically assigned and may change.

The host result verifies communication between two host-networked
containers. Access from macOS itself was not confirmed.

The overlay result verifies an attachable overlay on a single
Docker host. Communication between different hosts was not tested.

Evidence is stored in:

- evidence/task3-networking/containers.txt
- evidence/task3-networking/results.txt
- evidence/task3-networking/networks.txt

### Additional none-network experiment

A temporary container started with --network none had an empty
IPv4 routing table.

Connecting to the running application container failed with
ENETUNREACH: Network is unreachable.

An earlier interface-list assertion was too strict for this
environment. The final check verified routing and connection
behavior instead.

### Cleanup

Remove the demonstration containers and its Compose-managed networks:

```bash
docker compose -f docker-compose.networking.yaml down
```

If Swarm was created only for this experiment, leave it:

```bash
docker swarm leave --force
```

## References

- [Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
- [Compose startup order](https://docs.docker.com/compose/how-tos/startup-order/)
- [Bridge networking](https://docs.docker.com/engine/network/drivers/bridge/)
- [Host networking](https://docs.docker.com/engine/network/drivers/host/)
- [Overlay networking](https://docs.docker.com/engine/network/drivers/overlay/)
- [None networking](https://docs.docker.com/engine/network/drivers/none/)
