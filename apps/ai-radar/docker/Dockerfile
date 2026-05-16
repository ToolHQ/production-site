# syntax=docker/dockerfile:1.7
#
# AI Radar — unified Rust builder (cargo-chef) for API + CLI images.
#
# Build examples (from apps/ai-radar):
#   docker buildx build -f docker/Dockerfile --target runtime-api --build-arg BIN_NAME=ai-radar-api …
#   docker buildx build -f docker/Dockerfile --target runtime-cli --build-arg BIN_NAME=ai-radar …
#
# chef cook + registry/target cache mounts are shared between targets so a deploy
# that builds API then CLI reuses compiled dependencies (T-200).

# ── Toolchain + cargo-chef ─────────────────────────────────────────────────
FROM --platform=$BUILDPLATFORM rust:1.88-slim-bookworm AS chef

ARG TARGETARCH
ARG BUILDPLATFORM

ENV CARGO_TERM_COLOR=never \
    CARGO_INCREMENTAL=0 \
    RUSTFLAGS="-C strip=symbols" \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    build-essential pkg-config \
 && ARCH="$(uname -m)" \
 && if [ "$ARCH" = "x86_64" ] && [ "$TARGETARCH" = "arm64" ]; then \
      apt-get install -y --no-install-recommends gcc-aarch64-linux-gnu ; \
    elif [ "$ARCH" = "aarch64" ] && [ "$TARGETARCH" = "amd64" ]; then \
      apt-get install -y --no-install-recommends gcc-x86-64-linux-gnu ; \
    fi \
 && rm -rf /var/lib/apt/lists/* \
 && cargo install cargo-chef --locked

WORKDIR /workspace

RUN set -eux; \
  case "$TARGETARCH" in \
    amd64) RUST_TARGET=x86_64-unknown-linux-gnu; LINKER=x86_64-linux-gnu-gcc ;; \
    arm64) RUST_TARGET=aarch64-unknown-linux-gnu; LINKER=aarch64-linux-gnu-gcc ;; \
    *) echo >&2 "unsupported TARGETARCH=$TARGETARCH"; exit 1 ;; \
  esac; \
  echo "$RUST_TARGET" > rust-target.txt; \
  rustup target add "$RUST_TARGET"; \
  ARCH="$(uname -m)"; \
  NEED_CROSS=0; \
  case "$ARCH" in \
    x86_64) [ "$TARGETARCH" != "amd64" ] && NEED_CROSS=1 ;; \
    aarch64) [ "$TARGETARCH" != "arm64" ] && NEED_CROSS=1 ;; \
    *) echo >&2 "unexpected builder uname $ARCH"; exit 1 ;; \
  esac; \
  if [ "$NEED_CROSS" -eq 1 ]; then \
    mkdir -p .cargo; \
    printf '[target.%s]\nlinker = "%s"\n' "$RUST_TARGET" "$LINKER" > .cargo/config.toml; \
  fi

# ── Recipe (dependency fingerprint) ─────────────────────────────────────────
FROM chef AS planner

COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY crates/ai-radar-core/Cargo.toml crates/ai-radar-core/Cargo.toml
COPY crates/ai-radar-api/Cargo.toml  crates/ai-radar-api/Cargo.toml
COPY crates/ai-radar-cli/Cargo.toml  crates/ai-radar-cli/Cargo.toml

RUN mkdir -p crates/ai-radar-core/src crates/ai-radar-api/src crates/ai-radar-cli/src \
 && echo 'pub const VERSION: &str = "0.0.0-stub";' > crates/ai-radar-core/src/lib.rs \
 && printf 'fn main() {}\n' > crates/ai-radar-api/src/main.rs \
 && printf 'fn main() {}\n' > crates/ai-radar-cli/src/main.rs

RUN --mount=type=cache,id=ai-radar-cargo-registry,target=/usr/local/cargo/registry \
    cargo chef prepare --recipe-path recipe.json

# ── Compile dependencies + application binary ───────────────────────────────
FROM chef AS builder

ARG BIN_NAME=ai-radar-api

COPY --from=planner /workspace/recipe.json recipe.json

RUN --mount=type=cache,id=ai-radar-cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=ai-radar-cargo-target,target=/workspace/target \
    RUST_TARGET="$(cat rust-target.txt)" \
 && cargo chef cook --release --locked --recipe-path recipe.json \
      --bin "$BIN_NAME" --target "$RUST_TARGET"

COPY crates/ crates/
COPY migrations/ migrations/

RUN --mount=type=cache,id=ai-radar-cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=ai-radar-cargo-target,target=/workspace/target \
    RUST_TARGET="$(cat rust-target.txt)" \
 && cargo build --release --locked --bin "$BIN_NAME" --target "$RUST_TARGET" \
 && cp "target/$RUST_TARGET/release/$BIN_NAME" "/workspace/${BIN_NAME}.binary"

# ── API runtime ─────────────────────────────────────────────────────────────
FROM --platform=$TARGETPLATFORM gcr.io/distroless/cc-debian12:nonroot AS runtime-api

LABEL org.opencontainers.image.title="ai-radar-api" \
      org.opencontainers.image.description="AI Radar Decision Engine — HTTP API" \
      org.opencontainers.image.source="https://github.com/ToolHQ/production-site" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /app

COPY --from=builder /workspace/ai-radar-api.binary /usr/local/bin/ai-radar-api

ENV AI_RADAR_API_BIND=0.0.0.0:8080 \
    AI_RADAR_LOG_LEVEL=info

EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/ai-radar-api"]

# ── CLI runtime ─────────────────────────────────────────────────────────────
FROM --platform=$TARGETPLATFORM gcr.io/distroless/cc-debian12:nonroot AS runtime-cli

LABEL org.opencontainers.image.title="ai-radar-cli" \
      org.opencontainers.image.description="AI Radar Decision Engine — CronJob CLI" \
      org.opencontainers.image.source="https://github.com/ToolHQ/production-site" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /app

COPY --from=builder /workspace/ai-radar.binary /usr/local/bin/ai-radar

ENV AI_RADAR_LOG_LEVEL=info

USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/ai-radar"]
CMD ["--help"]
