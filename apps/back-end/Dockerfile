# syntax=docker/dockerfile:1
FROM node:22.13.0-alpine3.21 AS base
# FROM node:22.6.0-alpine3.20 AS base
# RUN apk add --no-cache --no-progress curl git make g++
RUN apk add --no-cache --no-progress curl busybox-extras
USER node
WORKDIR /usr/src/app

FROM base AS intermediate
ARG NPM_OMIT_DEV=dev
ENV NPM_OMIT_DEV=$NPM_OMIT_DEV
USER root
COPY dnor-root-ca.pem /usr/local/share/ca-certificates/dnor-root-ca.crt
RUN apk add --no-cache ca-certificates git make g++ python3 && update-ca-certificates
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/dnor-root-ca.crt
ENV NODE_OPTIONS=--use-openssl-ca
USER node
COPY package.json package-lock.json tsconfig.json dnor-root-ca.pem ./
RUN --mount=type=secret,id=npmrc,target=/tmp/npmrc.secret,uid=1000,gid=1000,mode=0400 \
    grep -v '^cafile=' /tmp/npmrc.secret > .npmrc && \
    npm ci --omit=optional --omit=peer --omit=$NPM_OMIT_DEV --no-audit --no-fund
COPY --chown=node:node . .
RUN ["npm", "run", "build"]

FROM base
COPY --from=intermediate /usr/src/app/node_modules ./node_modules
COPY --from=intermediate /usr/src/app/dist ./dist
COPY resources schemas package*.json tsconfig.json ./
COPY --chown=node:node . .
CMD ["node", "--enable-source-maps", "--experimental-loader=elastic-apm-node/loader.mjs", "dist/app.js"]
