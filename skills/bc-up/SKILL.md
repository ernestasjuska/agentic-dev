---
name: bc-up
description: Start a named Business Central instance on this machine, against the shared SQL Server and the shared Traefik proxy. Use when asked to start, create, spin up or restart a BC instance or dev environment, or to add a second BC version alongside an existing one. Not for BC SaaS sandboxes and not for BC on Windows containers.
---

# Start a BC instance

Each instance is its own compose project named `bc-<name>` on the shared
`bcnet` network. It owns neither the database server nor the proxy, so
starting and stopping one never disturbs the others.

```
pwsh ./scripts/bc-up.ps1 <name> [-BcRepo <path>] [-AgentWebClient] [-Json]
```

## Before the first instance

Both shared services must be running. Start them with the `mssql-up` and
`traefik-up` skills. `bc-up` reads the SA password and the public host from
what those two saved, so they do not have to be repeated here.

## Creating an instance

The first run needs values that are then remembered in a manifest at
`<platform>/instances/<name>.env`. If any are missing the script stops and
names them. Ask the user for the ones you cannot derive rather than inventing
them:

| Parameter | Needed | Notes |
|---|---|---|
| `-BcRepo` | always, first run | Path to the BcOnLinux checkout. Supplies the image and the entrypoint. |
| `-PublicHost` | if no shared proxy yet | `host:port` the browser uses. |
| `-SaPassword` | if no shared SQL yet | |
| `-AadAppId`, `-AadTenantId`, `-AadUserUpn` | only for Entra sign-in | `-AadUserUpn` must be the **token's email claim**, not the directory UPN. |
| `-HttpsPfxPassword` | if the backend serves TLS | Defaults to the `/certs/bc.pfx` mounted from the cert directory. |
| `-AgentWebClient` | to let an agent drive the UI | Adds a second web client at `/<name>dev` on NavUserPassword. |
| `-AppsDir` | to publish your own apps at boot | Directory of `.app` files, mounted read-only. Re-run to pick up new files. |

Later runs need only the name.

## Two ways in

`/<name>` serves whatever sign-in the instance is configured for, Entra when
the `-Aad*` parameters are set. `-AgentWebClient` adds `/<name>dev`, a second
front end on the same service tier that always uses NavUserPassword with
`BC_SERVER_USERNAME` / `BC_SERVER_PASSWORD`.

That split exists because an agent has no Entra account, and switching the
shared web client to NavUserPassword to let one in takes Entra away from every
person who does have one. Both front ends show the same data.

The instance also bind-mounts the repo's `scripts/` over `/bc/scripts`, so an
edit to `entrypoint.sh` or `start-webclient.sh` applies on the next container
start with no image rebuild.

## What it does

1. Allocates a free contiguous host port block and records it, so instances
   never collide. With base 7000 the dev endpoint is 7049, OData 7048, API
   7052, web client 7080.
2. Generates the instance compose by running `docker compose config` over the
   BcOnLinux repo and taking its `bc` service. It is generated, not copied, so
   the instance tracks upstream changes. `depends_on` is dropped: the shared
   SQL Server is not in this project, and the BC entrypoint waits for SQL
   itself.
3. Routes the web client at `https://<public-host>/<name>/` by setting
   `BC_WEBCLIENT_PATHBASE` and attaching Traefik labels. BC serves under the
   prefix itself, so no prefix stripping is involved.
4. Waits for the container healthcheck and then for the web client, which
   starts tens of seconds later.

## Pitfalls

- **Entra redirect URIs are per path.** An instance at `/bc28/` needs
  `https://<public-host>/bc28/SignIn` and `.../bc28/OAuthLanding.htm`
  registered on the app. Sign-in fails at Microsoft otherwise.
- **The artifact cache is shared** as the external volume `bc-artifacts`, on
  purpose: it is a read-only download cache and re-fetching it per instance
  costs gigabytes. The service and assembly-cache volumes stay per instance.
- **A recreate forces a fresh sign-in.** BC does not persist DataProtection
  keys, so auth cookies stop validating.
- Report the endpoints from the `bc-describe` skill rather than assuming
  default ports. Only the first instance gets the familiar 7049.
