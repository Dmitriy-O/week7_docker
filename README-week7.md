# Week 7 — Advanced Docker Practices

This document describes Task 1: Docker image optimization, and
Task 2: a local Django and PostgreSQL environment using Docker Compose.

## Task 1 — Docker Image Optimization

### Dockerfile design

The main Dockerfile has two stages:

- builder: installs compilation tools, verifies and builds curl,
  installs Python dependencies, and prepares static assets.
- runtime: contains the application, its Python dependencies,
  selected curl files, and required runtime libraries.

The application runs as user app with UID 10001.
Build tools are not copied into the final runtime stage.

### Improvements

- Added Gunicorn to requirements.txt to match the startup command.
- Declared the final Django and PyJWT versions in requirements.txt,
  removing a second installation that replaced earlier versions.
- Installed dependencies before copying application source.
- Added a BuildKit cache mount for pip without including the package
  cache in image layers.
- Separated dependency permission processing from application files
  to improve caching when only application source changes.
- Used .dockerignore to exclude secrets, local environments,
  infrastructure files, evidence, and comparison Dockerfiles.

CHANGELOG.md must remain available: hc/settings.py reads it during
initialization. Excluding it caused manage.py compress to fail.

### Single-stage versus multi-stage experiment

The comparison used the same application source, Python base image,
requirements, and linux/arm64 architecture.

| Image | Size in bytes | Decimal MB | GCC |
| --- | ---: | ---: | --- |
| healthchecks:single | 856196937 | 856.20 | Available |
| healthchecks:multi | 373737475 | 373.74 | Absent |

The multi-stage comparison image is 482459462 bytes smaller:
a reduction of 56.35% relative to the constructed single-stage image.

The Week 6 Dockerfile already used multiple stages. This experiment
demonstrates their benefit against the single-stage alternative;
it is not a 56.35% improvement over Week 6.

Both images passed:
- Django WSGI initialization;
- Gunicorn and PycURL imports;
- PostgreSQL connection through Django.

These checks do not cover every application feature.

### Build measurements

| Recorded scenario | Time |
| --- | ---: |
| Build with Docker layer cache disabled | 159.81 seconds |
| Rebuild using Docker layer cache | 12.15 seconds |

The rebuild still executed application copy and permission steps.
BuildKit cache mounts can retain data even with --no-cache.
These measurements describe different cache conditions; they do not
isolate a speed improvement over the original Dockerfile.

The main Dockerfile subsequently received the permission-step
ordering change. Its final size is recorded separately in
evidence/task1-final-image.txt.

### Reproduce the comparison

Build both variants:

    docker build --platform linux/arm64 -f Dockerfile.single -t healthchecks:single .
    docker build --platform linux/arm64 -f Dockerfile.multistage -t healthchecks:multi .

Inspect their sizes:

    docker image inspect healthchecks:single healthchecks:multi --format 'TAGS={{json .RepoTags}} SIZE_BYTES={{.Size}}'

Build the application image used by Compose:

    docker build --platform linux/arm64 -t healthchecks:week7-task1 .

### Tradeoffs

Multi-stage builds reduce the contents of the distributed image.
They do not inherently make Python code execute faster.

Build tools and intermediate results can still occupy space in the
local builder cache even though they are absent from the final image.

Optimizing image contents requires checking application dependencies
before removing files or libraries.

## Task 2 — Docker Compose for Local Development

### Services

docker-compose.yaml defines project week7-healthchecks:

| Service | Purpose | Address |
| --- | --- | --- |
| web | Django served by Gunicorn | http://localhost:8000 |
| db | PostgreSQL 17 | db:5432 within the Compose network |

Only web publishes a host port, bound to 127.0.0.1.
PostgreSQL is accessed by the application through the internal network.

The database has a health check. The web service depends on the
database being healthy.

### Local configuration

Create .env only if it does not already exist:

    test -e .env || cp .env.example .env
    chmod 600 .env

Fill in DJANGO_SECRET_KEY and POSTGRES_PASSWORD.
Generate independent random values using:

    openssl rand -hex 32

Compose maps these local values into container environment variables:
- DJANGO_SECRET_KEY becomes SECRET_KEY in web.
- POSTGRES_PASSWORD becomes DB_PASSWORD in web.
- POSTGRES_PASSWORD is passed to db for initial database setup.

The .env file is excluded from Git and the Docker build context.
It is a plaintext local configuration file, not an encrypted store.
Compose secrets are not configured.

### First-time startup

Run from the repository root:

    docker compose -f docker-compose.yaml config --quiet
    docker compose -f docker-compose.yaml build web
    docker compose -f docker-compose.yaml up -d --wait --wait-timeout 90 db
    docker compose -f docker-compose.yaml run --rm --no-deps web python manage.py migrate --noinput
    docker compose -f docker-compose.yaml up -d --no-build web

Open http://localhost:8000.

### Development workflow

Inspect services and logs:

    docker compose -f docker-compose.yaml ps
    docker compose -f docker-compose.yaml logs --tail=60 web

Source code is copied into the image. After changing code or dependencies:

    docker compose -f docker-compose.yaml build web
    docker compose -f docker-compose.yaml up -d --no-build --no-deps --force-recreate web

Apply migrations separately when application updates include them.
Building an image does not change the existing database schema.

Open PostgreSQL:

    docker compose -f docker-compose.yaml exec db psql -U hc -d hc

Inside psql:
- \dt lists tables.
- \d django_migrations shows table structure.
- \r clears an unfinished query.
- \q exits to the host terminal.

### Persistent database storage

The db service mounts postgres-data at /var/lib/postgresql/data.

The top-level volumes declaration tells Compose to manage this named
volume with default settings. It does not contain SQL or database rows.

The project name and logical volume name produce:
week7-healthchecks_postgres-data.

Inspect it with:

    docker volume inspect week7-healthchecks_postgres-data

On macOS, its mountpoint is inside Docker Desktop's Linux VM.

Persistence was verified:
1. django_migrations contained 205 rows.
2. Containers and the project network were removed using compose down.
3. Containers were recreated without rerunning migrations.
4. django_migrations still contained 205 rows.
5. HTTP returned 200.

Stop the project while preserving database data:

    docker compose -f docker-compose.yaml down

Do not add -v when retaining data: it removes the project's named volumes.

Changing POSTGRES_PASSWORD in .env does not update a database role's
password in an already initialized PostgreSQL data directory.

### Benefits and limitations

Compose provides a shared database version, network configuration,
environment mappings, and startup procedure. Developers do not need
to install PostgreSQL directly on their computers.

SMTP is not configured, so email-dependent features are not validated.

A previous Week 6 container occupied port 8000. Stopping that specific
container freed the port. Recreating web restored the expected network
attachment and port publication after its earlier failed startup.

