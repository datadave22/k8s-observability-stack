# 1.25, not 1.22: the Trivy scan in CI caught CVE-2025-68121, a CRITICAL
# crypto/tls certificate-validation bug fixed in the Go 1.22.x line's
# stdlib no later than 1.24.13/1.25.7. 1.25-alpine currently resolves to
# 1.25.12, well past the fix.
FROM golang:1.25-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./

# CGO_ENABLED=0 produces a static binary so the final image can be
# scratch-adjacent alpine with no libc dependency to match; -trimpath and
# -ldflags="-s -w" drop debug symbols/paths that only matter in dev.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/go-metrics-app .

# 3.22, not 3.19: the same Trivy run flagged alpine:3.19 as EOL
# ("no longer supported by the distribution"), meaning it stops receiving
# security patches entirely - any future CVE in an Alpine package would be
# permanently unfixable at that base image, not just currently unpatched.
FROM alpine:3.22

RUN apk add --no-cache ca-certificates \
    && addgroup -S app && adduser -S app -G app

COPY --from=builder /out/go-metrics-app /usr/local/bin/go-metrics-app

USER app
EXPOSE 5000

ENTRYPOINT ["/usr/local/bin/go-metrics-app"]
