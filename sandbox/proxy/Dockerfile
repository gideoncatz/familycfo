# Egress proxy for the sandbox: the sandbox sits on an internal Docker network with no route out, and reaches the
# internet only through this container, which allows the hosts in allowlist and nothing else (not the host machine's
# own services, the LAN, or any other site). It also forwards the web UI port to the sandbox.
FROM alpine:3.20
RUN apk add --no-cache tinyproxy socat
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY allowlist /etc/tinyproxy/allowlist
USER tinyproxy
