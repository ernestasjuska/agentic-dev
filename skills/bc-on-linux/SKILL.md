---
name: bc-on-linux
description: Run Microsoft Dynamics 365 Business Central on Linux with Docker Compose using StefanMaron/MsDyn365Bc.On.Linux — start the stack, compile and publish an AL app through the dev endpoint, run AL tests, trim the installed app set for faster boots, and reach the web client through a proxy or tunnel. Use when standing up a disposable BC environment on Linux or in CI, publishing an AL extension to one, or working out why the container will not boot or an app will not publish. Not for BC on Windows containers, and not for SaaS sandboxes.
---

# Business Central on Linux

Microsoft ships no Linux build of the BC service tier. This project runs the
unmodified Windows .NET binaries under a `DOTNET_STARTUP_HOOKS` assembly that
patches the Win32 calls at runtime. SQL Server is the real Microsoft Linux
build in a second container.

## Start it

```bash
git clone https://github.com/StefanMaron/MsDyn365Bc.On.Linux.git
cd MsDyn365Bc.On.Linux
docker compose up -d --wait
```

Needs Docker with Compose v2, `python3`, `curl`, `unzip`, ~4 GB RAM and ~3.5 GB
disk for artifacts. No .NET SDK on the host unless you compile AL from the CLI.

First boot downloads ~3.4 GB and takes several minutes; later boots are one to
two minutes. `--wait` returns when the healthcheck passes, which gates the
service tier only.

Set variables per shell. The `VAR=value command` prefix is POSIX-only:

```bash
BC_VERSION=28.4 docker compose up -d --wait
```

```powershell
$env:BC_VERSION = "28.4"; docker compose up -d --wait
```

## Endpoints and credentials

| Purpose | URL |
|---|---|
| Dev (publish, symbols) | `http://localhost:7049/BC/dev` |
| OData v4 | `http://localhost:7048/BC/ODataV4` |
| API v2.0 | `http://localhost:7052/BC/api/v2.0` |
| Web client (opt-in) | `http://localhost:8080` |

Sign in as `BCRUNNER` / `Admin123!`. The user is deliberately not `admin`, so
test code that deletes a user called ADMIN cannot end its own session. Override
with `BC_SERVER_USERNAME` / `BC_SERVER_PASSWORD`. These are the project's
published defaults — never expose these ports to an untrusted network without
changing them first.

Verify the tier is serving:

```bash
curl -sf -u BCRUNNER:Admin123! http://localhost:7048/BC/ODataV4/Company
```

## Compile and publish an AL app

Pick the compiler by BC major: **AL major = BC major − 11** (BC 28 → AL 17).
Let the repo resolve it rather than hardcoding a version:

```bash
python3 scripts/resolve-al-tool-version.py 28.4            # tool version
python3 scripts/resolve-al-tool-version.py 28.4 --runtime  # app.json runtime
bash scripts/install-al-compiler.sh 28.4                   # installs, prints AL_BIN_DIR
```

Pull symbols from the running dev endpoint into `.alpackages` — `System`,
`System Application`, `Base Application`, `Application`, `Business Foundation`:

```bash
curl -sf -u BCRUNNER:Admin123! \
  "http://localhost:7049/BC/dev/packages?publisher=Microsoft&appName=Base%20Application&appVersion=0.0.0.0" \
  -o ".alpackages/Base Application.app"
```

Compile, then publish:

```bash
AL compile "/project:." "/packagecachepath:.alpackages" "/out:MyApp.app"
curl -u BCRUNNER:Admin123! -X POST \
  -F "file=@MyApp.app;type=application/octet-stream" \
  "http://localhost:7049/BC/dev/apps?SchemaUpdateMode=forcesync"
```

HTTP 200 means published. **A 422 is not automatically benign — read the body.**
"already deployed/installed/published" is fine. `AL1024` means a dependency is
not installed in the database, which putting a symbol in `.alpackages` does not
fix. `scripts/publish-app.sh` draws that distinction; source it rather than
treating every 422 as success.

An `app.json` declaring `"application"` needs the Application umbrella app
installed. Without it the publish fails `AL1024` and then cascades into
misleading `AL0185: Table 'X' is missing` errors for every Base Application
table the code touches.

To expose a codeunit procedure over OData, mark it `[ServiceEnabled]` and insert
a `Tenant Web Service` row from an install codeunit. It is then reachable as an
unbound action at `/ODataV4/<ServiceName>_<ProcedureName>?company=<name>`.

## Run AL tests

The test toolkit is published on first boot, so no extra setup is needed:

```bash
./scripts/run-tests.sh --app MyTestApp.app --junit-output ./results.xml
```

## Trim the app set for faster boots

A stock boot installs about a hundred extensions. `BC_CLEAR_ALL_APPS=selective`
with a keep-set removes the ones the project does not depend on. Compute the set
from your own `app.json` rather than hand-listing GUIDs:

```bash
python3 scripts/resolve-keep-app-ids.py --app-json app.json --artifact-dir <artifacts>
```

Measured on BC 28.4, warm boots, one host: 101 apps / 96 s / 2.25 GiB RSS against
4 apps / 53 s / 1.17 GiB. Creating and posting a sales order still works on the
four-app set, because Base Application survives.

**What the trim costs:** cleared apps take their endpoints with them. API v2.0
lives in `_Exclude_APIV2_`, so `/api/v2.0/...` starts returning 404 while OData
v4 and the dev endpoint keep working. Add `BC_SKIP_APP_PUBLISH=true` to also skip
publishing the test toolkit when you are not running tests.

## Web client behind a proxy or tunnel

```bash
BC_WEBCLIENT=1 docker compose up -d --wait
```

It starts 20 to 40 seconds *after* the container reports healthy, because the
healthcheck gates the service tier only. Connection refused immediately after
`--wait` returns is expected; wait and retry.

Three things bite once it is not on plain `localhost`:

- **Do not set `BC_WEBCLIENT_REQUIRE_SSL=1` for a TLS-terminating proxy that
  forwards plain HTTP.** It sets the antiforgery cookie policy to `Secure`
  always, and the app then checks `Request.IsHttps`, which is false because it
  never processes `X-Forwarded-Proto`. `/SignIn` returns HTTP 500 with
  `AntiforgeryOptions.Cookie.SecurePolicy = Always, but the current request is
  not an SSL request`. Leave it off and let the proxy handle the upgrade.
- **Check that `BC_WEBCLIENT_PUBLIC_URL` reaches the container.** The entrypoint
  reads it to set `PublicWebBaseUrl`, but it has to be listed in the `bc`
  service's `environment:` block in `docker-compose.yml` to get there. If it is
  missing, setting it on the host shell silently does nothing.
- **The URL has no `/BC` segment.** On Windows that is an IIS application alias,
  not something BC derives from `ServerInstance`; Kestrel binds the root here.
  `BC_WEBCLIENT_PATHBASE=/BC` adds it. `?tenant=default` is absent because the
  deployment is single-tenant.

Redirects are built from the request `Host`, so a proxy that changes the public
port must rewrite the `Location` header or the redirect points at a port nothing
is listening on.

Known gap: record images (customer and item pictures) never render. `/img?...`
returns 404 because `System.Drawing.Common` throws unconditionally on Linux.

## Pitfalls

- **The database is on a tmpfs.** `/var/opt/mssql/data` is memory-backed, so the
  demo database is restored fresh on every container recreate and nothing saved
  in it survives. Fine for dev and CI; never a store of record.
- **Full-Text Search is absent.** No official SQL Server Linux image ships it, so
  an app using `OptimizeForTextSearch = true` fails to install. Use
  `BC_SQL_IMAGE=ghcr.io/stefanmaron/msdyn365bc.on.linux/mssql:2022-fts`.
- **Do not cache BC artifacts in CI.** Microsoft moves the revision build several
  times a day, so the key is invalidated about as often as it is written, and at
  ~3 GB per version the cache thrashes before anything is reused.
- **One BC per docker host unless you namespace it.** Compose derives the project
  name from the directory and the ports are fixed, so a second stack tears the
  first one down mid-run. Give each `-p <name>` and its own port set.
- `docker compose down` keeps the artifact cache; `down -v` forces a full
  re-download.
