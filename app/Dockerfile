FROM golang:1.22-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./

# CGO_ENABLED=0 produces a static binary so the final image can be
# scratch-adjacent alpine with no libc dependency to match; -trimpath and
# -ldflags="-s -w" drop debug symbols/paths that only matter in dev.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/go-metrics-app .

FROM alpine:3.19

RUN apk add --no-cache ca-certificates \
    && addgroup -S app && adduser -S app -G app

COPY --from=builder /out/go-metrics-app /usr/local/bin/go-metrics-app

USER app
EXPOSE 5000

ENTRYPOINT ["/usr/local/bin/go-metrics-app"]
