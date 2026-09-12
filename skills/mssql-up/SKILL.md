---
name: mssql-up
description: Start the shared SQL Server that Business Central instances on this machine use, on the shared docker network. Use when asked to start the database server, when a BC instance cannot reach SQL, or as the first step before creating the first BC instance. Not for SQL Server in a cloud subscription and not for a database embedded in a single application's compose file.
---

# Start the shared SQL Server

```
pwsh ./scripts/mssql-up.ps1 [-SaPassword <pw>] [-Port 11433] [-Ephemeral] [-Json]
```

One SQL Server in its own compose project (`bc-mssql`), serving every BC
instance. It is deliberately not part of any instance, so stopping or deleting
an instance never touches the databases.

`-SaPassword` is needed only on the first run. Afterwards it is read back from
the saved environment file, because changing it would orphan the existing
databases. Ask the user for it rather than inventing one.

The script creates the shared `bcnet` network if it does not exist, then waits
for the container healthcheck before reporting success.

## Persistence

Data lives on a named volume, not tmpfs. A shared server that wiped every
instance's database on restart would be useless. `-Ephemeral` switches to
tmpfs for a disposable, faster setup, and is the right choice only when every
instance on the machine is disposable too.

The artifacts volume is mounted read-only as well. The BC entrypoint imports a
custom licence through `OPENROWSET BULK`, which reads the file from SQL
Server's filesystem rather than the BC container's.

## Related

Use the `bc-ps` skill to see whether it is already running before starting it,
and the `mssql-down` skill to stop it.
