FROM rust:1.86-slim-bullseye as builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs
RUN cargo build --release
RUN rm -r src
COPY . .
RUN cargo build --release

FROM debian:bullseye-slim
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/vanilla_rust_api /usr/local/bin/
CMD ["/usr/local/bin/vanilla_rust_api"]
