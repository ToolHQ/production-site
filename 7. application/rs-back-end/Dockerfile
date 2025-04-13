FROM rust:1.86-alpine as builder
RUN apk add --no-cache musl-dev gcc
WORKDIR /app
COPY . .
RUN cargo build --release

FROM alpine:latest
RUN apk add --no-cache ca-certificates curl
COPY --from=builder /app/target/release/rust_api /usr/local/bin/app
EXPOSE 3000
CMD ["app"]
