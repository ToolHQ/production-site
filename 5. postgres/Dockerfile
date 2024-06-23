# syntax=docker/dockerfile:1
FROM postgres:16.3-alpine3.20
# FROM postgres:17beta1-alpine3.20

# # Install build dependencies
# RUN apk add --no-cache \
#   postgresql-dev \
#   build-base \
#   wget \
#   ca-certificates \
#   libxml2-dev \
#   libxslt-dev \
#   git \
#   python3 \
#   py3-pip

# # Create a virtual environment and install pgxnclient
# RUN python3 -m venv /venv && \
#   . /venv/bin/activate && \
#   pip install pgxnclient

# # Clone pg_query repository and install
# RUN git clone -b 16-latest https://github.com/pganalyze/libpg_query.git && \
#   cd libpg_query && \
#   make

# # Clean up
# RUN apk del \
#   build-base \
#   wget \
#   ca-certificates \
#   libxml2-dev \
#   libxslt-dev \
#   git \
#   py3-pip && \
#   rm -rf /var/cache/apk/* 

# Expose the PostgreSQL port
EXPOSE 5432