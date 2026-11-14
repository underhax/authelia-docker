FROM ghcr.io/authelia/authelia:4.39.28@sha256:bd97cff4fcbf715b5ff1f9ae286afbe6033afce385302520b0368122d43a6f54 AS donor

FROM donor AS runtime-libs

SHELL ["/bin/ash", "-o", "pipefail", "-c"]

RUN mkdir -p /out && \
    find -L /lib* /usr/lib* -type f 2>/dev/null | \
      while read -r f; do \
        dir="/out$(dirname "$f")" && \
        mkdir -p "$dir" && \
        cp -L "$f" "$dir/"; \
      done

FROM golang:1.27.4-alpine3.24@sha256:0a5f7fe796599ff487605987432e7619ae45beeb2fba4c2ce0b907879932aebf AS go-builder

WORKDIR /build

COPY go.mod ./
COPY probe/ ./probe/

RUN mkdir -p /out/config /out/data /out/logs /out/etc/ssl/certs && \
    chmod 0755 /out/config /out/etc /out/etc/ssl /out/etc/ssl/certs && \
    chmod 0700 /out/data /out/logs && \
    cp /etc/ssl/certs/ca-certificates.crt /out/etc/ssl/certs/ca-certificates.crt && \
    chmod 0444 /out/etc/ssl/certs/ca-certificates.crt && \
    CGO_ENABLED=0 go build -ldflags="-s -w" -trimpath -o /out/probe ./probe

FROM scratch

ENV X_AUTHELIA_CONFIG=/config/configuration.yml

COPY --from=runtime-libs /out/ /
COPY --from=go-builder /out/etc /etc
COPY --from=go-builder --chmod=0755 /out/config /config
COPY --from=go-builder --chmod=0700 /out/data /data
COPY --from=go-builder --chmod=0700 /out/logs /logs
COPY --from=donor --chmod=0555 /app/authelia /usr/local/bin/authelia
COPY --from=go-builder --chmod=0555 /out/probe /usr/local/bin/probe

ENTRYPOINT ["/usr/local/bin/authelia"]
