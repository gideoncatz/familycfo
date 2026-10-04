# Sandbox

Runs this project's dependencies — `npm install`, tests, typechecks, the dev servers — inside a Docker container, so
install scripts and package code never execute on your machine. You (and your editor, and Claude Code) edit the files
on the host as usual; only commands go through the sandbox.

```bash
sandbox/run.sh npm install          # first time; node_modules live in Docker volumes, not in the working tree
sandbox/run.sh npm test
sandbox/run.sh npm run typecheck
sandbox/run.sh npm run demo         # build demo.db with made-up data
sandbox/run.sh npm run dev:demo     # then open http://127.0.0.1:5180
sandbox/run.sh                      # a shell inside
sandbox/run.sh --stop               # stop this checkout's container (also stops a dev server left running)
sandbox/run.sh --reset              # and delete its node_modules volumes
```

Each checkout (including each git worktree) gets its own container and `node_modules` volumes. `SANDBOX_PORT` picks
the host port for the web UI when 5180 is taken.

## What it isolates

- The container sees only this checkout at `/app` — not your home directory, SSH keys, git or npm credentials, or the
  Docker socket. With Docker Desktop it also runs inside a VM.
- Non-root, no Linux capabilities, `no-new-privileges`, 4 CPUs / 4 GB / 1024 processes.
- No network route of its own. The container sits on an internal Docker network and reaches only the hosts in
  [proxy/allowlist](proxy/allowlist) — the npm registry, GitHub release downloads, nodejs.org, Yahoo Finance and the
  Bank of Israel — through a small proxy container. Your machine's own services (anything on `127.0.0.1`, e.g. a real
  FamilyCFO API), the LAN, other sites and external DNS are all unreachable. Refused hosts show up in
  `docker logs familycfo-sandbox-<id>-proxy`; add a line to the allowlist if something legitimate needs one.
- The web UI is published on `127.0.0.1` only, by the proxy container. The API isn't published; Vite proxies to it
  inside the sandbox.
- Paths the host acts on are read-only inside: `.git`, `.claude`, `.vscode`, `.idea`, every `CLAUDE.md` /
  `AGENTS.md` / `.mcp.json` / `.envrc`, and `sandbox/` itself. If the container is the first to create `.claude`, it
  writes to a throwaway tmpfs.
- After every command, `run.sh` warns if new files of those kinds appeared (e.g. a `CLAUDE.md` in a new folder).

## What it doesn't

- The rest of the source is writable — that's the point — so code in the container could change it. Review
  `git status` / `git diff` before committing, and don't run `npm` on the host for this project at all.
- The allowed hosts could still carry data out in principle (e.g. a request to GitHub). There's nothing secret inside
  to send, which is the point of keeping real data out.
- With Docker Desktop, the VM it runs in has your home folder shared into it, so a container escape (a kernel exploit)
  would reach it. Narrowing Docker Desktop's file sharing (Settings → Resources → File sharing) shrinks that.
- No real bank data or logins: never put `accounts.json`, `bank.db` or `data/` here. Puppeteer's Chrome isn't
  downloaded (`PUPPETEER_SKIP_DOWNLOAD=1`), so scraping isn't available, and the ✨ data chat needs the host's `claude`
  CLI, which isn't in the container.
- Your editor won't find `node_modules` on the host, so it can't resolve package types. That's deliberate — a
  TypeScript server loading the project's `typescript` package would run dependency code on the host.
