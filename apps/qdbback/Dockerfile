FROM node:16.6.0-alpine3.14
WORKDIR /tmp/build/app
RUN echo '{"commitTitle":null,"sha":null}' > version.json
COPY package*.json .npmrc ./
RUN ["npm", "ci"]

FROM node:16.6.0-alpine3.14
USER node
COPY --from=0 --chown=node:node /tmp/build/app /home/node/app
WORKDIR /home/node/app
COPY --chown=node:node . ./src/
CMD ["node", "src/index.js"]