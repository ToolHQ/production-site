# ---------- Stage 1: Build ----------
FROM node:24.11.0-alpine3.21 AS builder

# Install required build tools
RUN apk add --no-cache git make bash go

# Use local source (context is your already-cloned repo)
WORKDIR /src
COPY . .

# --- Build Web UI ---
WORKDIR /src/web-app
RUN corepack enable && corepack prepare yarn@stable --activate
# Allow yarn to update the lockfile for OpenMaxIO deps, then build
RUN yarn install && yarn build

# --- Build Console binary ---
WORKDIR /src
RUN make console

# ---------- Stage 2: Runtime ----------
FROM alpine:3.22
WORKDIR /app
COPY --from=builder /src/web-app/build ./web-app/build
COPY --from=builder /src/console ./console
CMD ["./console", "server"]
