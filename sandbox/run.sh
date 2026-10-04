#!/usr/bin/env bash
# Run a command for this checkout inside a Docker container, so dependency code never runs on the host.
#
#   sandbox/run.sh npm install         install (node_modules go to Docker volumes, not the working tree)
#   sandbox/run.sh npm test            any command, run in /app
#   sandbox/run.sh npm run dev:demo    then open http://127.0.0.1:5180 on the host
#   sandbox/run.sh                     a shell
#   sandbox/run.sh --stop              stop and remove this checkout's containers (volumes are kept)
#   sandbox/run.sh --reset             also delete its node_modules volumes
#
# The sandbox has no network route of its own: it reaches only the hosts in sandbox/proxy/allowlist, through a proxy
# container, which also publishes the web UI. SANDBOX_PORT picks the host port for it (default 5180).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
id="$(printf '%s' "$root" | sha256sum | cut -c1-12)"
image=familycfo-sandbox
name="familycfo-sandbox-$id"
proxy="$name-proxy"
net="$name-net"
port="${SANDBOX_PORT:-5180}"

remove() {
  docker rm -f "$name" "$proxy" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
}
case "${1:-}" in
  --stop) remove; exit 0 ;;
  --reset)
    remove
    docker volume rm "$name-nm" "$name-web-nm" >/dev/null 2>&1 || true
    exit 0 ;;
esac

docker build -q -t "$image" "$root/sandbox" >/dev/null
docker build -q -t "$image-proxy" "$root/sandbox/proxy" >/dev/null

if [ -z "$(docker ps -q -f "name=^$proxy$")" ] || [ -z "$(docker ps -q -f "name=^$name$")" ]; then
  remove
  docker network create --internal "$net" >/dev/null
  # The proxy is the only container with a route out; it joins the internal network as well to serve the sandbox.
  docker run -d --name "$proxy" --init --read-only \
    --cap-drop ALL --security-opt no-new-privileges --memory 128m --pids-limit 128 \
    -p "127.0.0.1:$port:5180" \
    "$image-proxy" sh -c "tinyproxy -d & exec socat TCP-LISTEN:5180,reuseaddr,fork TCP:$name:5180" >/dev/null
  docker network connect "$net" "$proxy"
fi

if [ -z "$(docker ps -q -f "name=^$name$")" ]; then
  docker rm -f "$name" >/dev/null 2>&1 || true

  # Files the host runs or obeys (git, Claude Code, IDEs, this script) are read-only inside, so code in the
  # container can't plant a git hook, a Claude Code hook or instructions, or change the sandbox itself.
  protect=()
  while IFS= read -r -d '' p; do
    protect+=(-v "$p:/app/${p#"$root"/}:ro")
  done < <(find "$root" -name node_modules -prune \
    -o \( -name .git -o -name .claude -o -name .vscode -o -name .idea \) -print0 -prune \
    -o \( -name CLAUDE.md -o -name CLAUDE.local.md -o -name AGENTS.md -o -name .mcp.json -o -name .envrc \) -print0)
  protect+=(-v "$root/sandbox:/app/sandbox:ro")
  [ -e "$root/.claude" ] || protect+=(--mount type=tmpfs,dst=/app/.claude)

  # Bounded: the vitest pool sizes itself from the visible CPUs.
  docker run -d --name "$name" --init \
    --cap-drop ALL --security-opt no-new-privileges \
    --cpuset-cpus 0-3 --memory 4g --pids-limit 1024 \
    --network "$net" -e WEB_PORT=5180 \
    -e HTTP_PROXY="http://$proxy:8888" -e HTTPS_PROXY="http://$proxy:8888" \
    -e http_proxy="http://$proxy:8888" -e https_proxy="http://$proxy:8888" \
    -e NO_PROXY=localhost,127.0.0.1,::1 -e no_proxy=localhost,127.0.0.1,::1 -e NODE_USE_ENV_PROXY=1 \
    -v "$root:/app" \
    -v "$name-nm:/app/node_modules" -v "$name-web-nm:/app/web/node_modules" \
    -v "$image-npm-cache:/home/node/.npm" \
    "${protect[@]}" \
    "$image" sh -c 'socat TCP-LISTEN:5180,bind="$(hostname -i)",reuseaddr,fork TCP:127.0.0.1:5180 & exec sleep infinity' \
    >/dev/null
fi

# Files of the kinds above that appear during the run weren't protected (e.g. a CLAUDE.md in a new folder): flag them.
watched() {
  find "$root" -name node_modules -prune -o -path "$root/.git" -prune -o -path "$root/.claude" -prune \
    -o \( -name .git -o -name .claude -o -name CLAUDE.md -o -name CLAUDE.local.md -o -name AGENTS.md \
    -o -name .mcp.json -o -name .vscode -o -name .idea -o -name .envrc \) -print | sort
}
before="$(watched)"

tty=(-i); [ -t 0 ] && [ -t 1 ] && tty=(-it)
status=0
docker exec "${tty[@]}" "$name" "${@:-bash}" || status=$?

added="$(comm -13 <(printf '%s\n' "$before") <(watched))"
if [ -n "$added" ]; then
  printf '\n\033[33msandbox: the command created files the host may act on - review them before running git, Claude Code or an IDE here:\033[0m\n%s\n' "$added" >&2
fi
exit "$status"
