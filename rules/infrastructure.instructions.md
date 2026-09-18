---
applyTo: '**'
---

# This machine

One VM, 32 GB of RAM, no swap, several agents and several projects at once. Anything
long-lived is shared infrastructure, not scenery belonging to your project.

## Before you start a service

Run `docker ps` and look. These already exist and are meant to be reused:

- SQL Server for Business Central: container `bc-mssql`, shared by every BC instance.
  Skills `mssql-up`, `bc-ps`.
- Reverse proxy and the one published HTTPS port: container `bc-traefik`. Apps opt in
  with docker labels. Skill `traefik-up`.
- Docker network `bcnet` joins them.

Never start a second database server, proxy or tunnel because the first one is
inconvenient to configure. Never stop or delete a container you did not start: another
agent's demo is probably behind it.

Stop what you did start, once you are done with it.

## Shared infrastructure is the IT admin's call

Anything that outlives your task belongs to the admin: a new database server, a
reverse-proxy route, a devtunnel, an Aspire app left running, a container that should
survive a reboot. Ask for it instead of building your own.

One Claude Code session on this machine acts as IT admin. Find it with `ListAgents`, which
lists the live sessions, and `SendMessage` it your request. Session names are per-session
and change, so there is no fixed name to address: ask a peer whether it holds the admin
role, or say what you need and let it route you. No session answering, or you are not
Claude Code? Ask Ernestas in chat. Do not provision shared infrastructure yourself while
waiting.

## Azure

Subscription `T3 Codes` is development and testing, and this VM lives in it. Read it
freely: `az account show`, `az resource list`. Creating, resizing or deleting anything
there is the admin's call, not yours. Ask the CLI for ids rather than putting a
subscription id in a file.
