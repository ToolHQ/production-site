# syntax=docker/dockerfile:1
FROM node:22.2.0-alpine3.20 AS base
RUN apk add --no-cache --no-progress curl
USER node
WORKDIR /usr/src/app

FROM base AS intermediate
ARG NPM_OMIT_DEV=dev
ENV NPM_OMIT_DEV=$NPM_OMIT_DEV
COPY .npmrc package*.json tsconfig.json webpack.config.js ./
RUN npm ci --omit=optional --omit=peer --omit=$NPM_OMIT_DEV --no-audit --no-fund --verbose
COPY --chown=node:node . .
RUN ["npm", "run", "build"]

FROM base
COPY --from=intermediate /usr/src/app/node_modules ./node_modules
COPY --from=intermediate /usr/src/app/dist ./dist
COPY .npmrc package*.json tsconfig.json webpack.config.js ./
COPY --chown=node:node . .
CMD ["node", "--enable-source-maps", "dist/app.js"]