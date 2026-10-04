# Sandbox for running this project's dependencies (npm install, tests, dev servers) away from the host.
# Built and used by sandbox/run.sh; the source is bind-mounted at /app, node_modules live in Docker volumes.
FROM node:24-bookworm

# socat exposes the dev server: the app binds 127.0.0.1 only, so it forwards the container's own address to it.
RUN apt-get update \
 && apt-get install -y --no-install-recommends socat \
 && rm -rf /var/lib/apt/lists/*

# New named volumes copy these directories' ownership, so the non-root user can write to them.
RUN mkdir -p /app/node_modules /app/web/node_modules /home/node/.npm \
 && chown -R node:node /app /home/node/.npm

# The scraper's Chrome is only needed against real banks, which this sandbox is not for.
ENV PUPPETEER_SKIP_DOWNLOAD=1

USER node
WORKDIR /app
