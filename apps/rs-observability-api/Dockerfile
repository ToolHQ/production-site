# Estágio 1: Build do frontend Vite (Preact/TS)
FROM node:22-slim AS frontend-builder
WORKDIR /app/web-v2
COPY web-v2/package.json web-v2/package-lock.json ./
RUN npm ci --ignore-scripts
COPY web-v2/ ./
RUN npm run build

# Estágio 2: Build do servidor Rust (embed do dist via include_bytes!)
FROM rust:1.86-slim-bookworm AS backend-builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY config/external_nodes.json ./config/external_nodes.json
# web-v2/dist é embutido no binário Rust via include_str!/include_bytes! (compile-time)
COPY --from=frontend-builder /app/web-v2/dist ./web-v2/dist
RUN cargo build --release --bin rs-observability-api

# Estágio 3: Imagem final mínima
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV PORT=3000
ENV REPORTS_ROOT=/opt/reports

COPY --from=backend-builder /app/target/release/rs-observability-api /usr/local/bin/rs-observability-api
COPY reports-bundle /opt/reports

EXPOSE 3000
CMD ["/usr/local/bin/rs-observability-api"]

