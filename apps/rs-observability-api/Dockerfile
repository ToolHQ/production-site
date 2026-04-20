FROM rust:1.86-slim-bookworm AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY web ./web
RUN cargo build --release --bin rs-observability-api

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV PORT=3000
ENV REPORTS_ROOT=/opt/reports

COPY --from=builder /app/target/release/rs-observability-api /usr/local/bin/rs-observability-api
COPY reports-bundle /opt/reports

EXPOSE 3000
CMD ["/usr/local/bin/rs-observability-api"]

