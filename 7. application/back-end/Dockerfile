FROM docker-nexus.localhost/repository/docker-repo/node:20.13.1-alpine3.19 AS base
RUN apk add --no-cache --no-progress curl && \
  npm i typescript webpack webpack-cli ts-loader -g
USER node
WORKDIR /usr/src/app

FROM base AS intermediate
ARG NPM_OMIT_DEV=dev
ENV NPM_OMIT_DEV=$NPM_OMIT_DEV
COPY package*.json tsconfig.json webpack.config.js ./
RUN npm ci --omit=optional --omit=peer --omit=$NPM_OMIT_DEV --no-audit --no-fund
COPY --chown=node:node . .
RUN ["npm", "run", "build"]

FROM base
COPY --from=intermediate /usr/src/app/node_modules ./node_modules
COPY --from=intermediate /usr/src/app/dist ./dist
COPY package*.json tsconfig.json webpack.config.js ./
COPY --chown=node:node . .
CMD ["node", "dist/bundle.js"]