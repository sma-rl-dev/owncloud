# ownCloud - Deployment, Smoke, Seed, and Mutation Notes

## Quick Start

```bash
./tester-env deploy    # Build editable-source image, start container, auto-install (SQLite)
./tester-env seed      # Populate with deterministic Northwind Design Studio data
./tester-env verify    # Check install, login page, vendor bundle, and seed state
./tester-env reset     # Clean slate (stop + remove container + volume, keeps image)
```

## CLI Commands

| Command | Description |
|---------|-------------|
| `deploy` | Build image, start container, auto-install via `occ maintenance:install` (SQLite) |
| `seed` | Deterministic users, group, files, favorite, version, and shares (`tester-env-seed.sh`) |
| `verify` | Assert install + login form markup + `core/vendor` bundle + full seed state |
| `reset` | Stop container, remove container and data volume (keeps image) |
| `stop` | Stop container (preserves data) |
| `logs` | Follow container logs |
| `status` | Show container status and URL |

Options:

- `--run-id <id>` isolates container and volume names for parallel scenario runs.
- `--port <port>` binds the app to a specific host port (default: `8088`).
- `IMAGE_TAG` env (set by `scripts/rl-env`) overrides the image tag; manual runs use
  `tester-env-owncloud:dev`. `RUN_ID` never scopes the image name.

## Build

```bash
./tester-env deploy
```

Editable-source image `tester-env-owncloud:dev`: `php:8.3-apache` + `gd/intl/zip/exif/mbstring/curl/fileinfo/bcmath/pcntl/pdo_sqlite` + pecl `apcu/memcached/imagick`, `composer install --no-dev`, SQLite auto-install on first boot via `docker-entrypoint-tester-env.sh` (`occ maintenance:install`, `trusted_domains` localhost + host.docker.internal).

Repair 2026-09-04: the login page served form HTML but all 13 `core/vendor` JS files (jquery/underscore/backbone/...) 404 — `core/vendor` is not committed upstream, it is built via `yarn install` in `build/` (Makefile). `Dockerfile.tester-env` now installs node 20 + yarn 1.22.22, adds a cached yarn layer, and symlinks `core/vendor` to `build/node_modules/@bower_components`; `.dockerignore` excludes `.git`. Verify asserts login HTML contains `name="user"`/`type="password"`/`id="submit"` plus `/core/vendor/jquery.min.js` 200 (all 18 vendor refs on the login page return 200); admin POST login 303s to the Files app.

- Cold build ~10-12 min (PHP extension compile + pecl memcached/imagick); build fix needed `libssl-dev`+`libsasl2-dev` for pecl memcached pkg-config detection.
- 1-line template edit rebuilds in ~3s (apt+composer+pecl layers cached); source-mutability probe edit verified visible in `/index.php/login` HTML, then reverted.
- Caveats: redis/ldap/smb omitted.
- Port: `8088`
- URL: `http://localhost:8088`

Tooling provenance: this CLI plus `Dockerfile.tester-env`, `docker-entrypoint-tester-env.sh`, and `tester-env-seed.sh` were proven in `.work/prospects/owncloud` and moved here unchanged at fork time.

## Credentials

- Admin: `admin` / `admin12345`
- Seeded user: `tester` / `tester12345` (Alex Rivera)
- Seeded user: `teammate` / `teammate12345` (Sam Chen)

## Seed Data

```bash
./tester-env seed
```

Deterministic Northwind Design Studio state (`tester-env-seed.sh`, manifest in corpus `scenarios/owncloud/seed.manifest.json`):

- Users `tester` + `teammate` (+ admin), group `studio` with both members.
- 5 files: `welcome.txt`, `Projects/Website-Redesign/brief.txt` + `launch-checklist.md`, `Invoices/invoice-2026-08.txt`, `Notes/meeting-notes-2026-08-28.md`.
- `brief.txt` favorited at v2 (`Launch readiness: GREEN`, exactly 1 stored version, none elsewhere).
- User share `/Projects` -> `teammate` (permissions 31) + one link share on the invoice.

Determinism: reset -> deploy -> seed -> verify PASS; state fingerprint byte-identical across reset cycle; re-seed-on-top verify OK.

## Reset

```bash
./tester-env reset
```

Stops and removes the container and the `owncloud-data` named volume (keeps the image); `deploy` + `seed` returns to the identical seeded state.

## Browser Verification

Post-repair browser-checker PASS at `http://localhost:8088`:

- Login page renders (logo, username/password fields, Login button).
- Login `admin/admin12345` -> Files app; seeded `welcome.txt` visible (163 B).
- State-changing workflow: created folder `smoke-folder-0904` via + menu (list showed `1 folder and 1 file`), navigated in (breadcrumb All files > smoke-folder-0904, empty state), deleted via row menu (restored to `1 file`), logout returned to login page.
- Seed views: `tester` Files shows Invoices/Notes/Projects (Shared badge)/welcome.txt; `brief.txt` starred + preview renders; Favourites = `brief.txt` only; Shared with others = Projects (Sam Chen) + invoice link; `teammate` sees Projects from Alex Rivera.
- Browser-level create/delete folder round-trip restored the file list to baseline.

## Baseline

- Pinned tag: `v11.0.0` (latest stable, released 2026-07-30)
- Pinned SHA: `ad4be1919184c9ce1e6e5b9b592e6e00e513c337`
- Fork branch: `tester-env-baseline` (this file + tester-env tooling committed directly on top of the pinned tag)
