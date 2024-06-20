# syntax=docker/dockerfile:1
FROM postgres:16.3-alpine3.20
# FROM postgres:17beta1-alpine3.20

RUN apk update && \
  apk add --no-cache --virtual .build-deps \
  gcc \
  git \
  libc-dev \
  make \
  postgresql-dev

RUN git clone https://github.com/pganalyze/libpg_query.git

WORKDIR /libpg_query
RUN make
RUN make install

RUN apk del .build-deps
RUN rm -rf /libpg_query

CMD ["postgres"]
