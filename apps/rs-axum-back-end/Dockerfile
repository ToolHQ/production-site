# FROM rust:1.86-alpine as builder
# RUN apk add --no-cache musl-dev gcc
# WORKDIR /app

# # 1. Copie apenas os arquivos de dependência
# COPY Cargo.toml Cargo.lock ./
# RUN mkdir src && echo 'fn main() {println!("placeholder");}' > src/main.rs
# RUN cargo build --release
# RUN rm -rf src

# # 2. Agora copie o código real
# COPY . .
# RUN cargo build --release

# FROM alpine:latest
# RUN apk add --no-cache ca-certificates curl
# COPY --from=builder /app/target/release/rust_api /usr/local/bin/app
# EXPOSE 3000
# CMD ["app"]


FROM rust:1.88-slim-bullseye as builder
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
    heaptrack \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/rust_api /usr/local/bin/
# CMD ["heaptrack", "/usr/local/bin/rust_api"]
CMD ["/usr/local/bin/rust_api"]
