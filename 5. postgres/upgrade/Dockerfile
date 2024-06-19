# Start from an Alpine base image
FROM alpine:3.20

# Install dependencies for building PostgreSQL
RUN apk update && \
  apk add --no-cache \
  bash \
  gcc \
  git \
  libc-dev \
  make \
  openssl-dev \
  readline-dev \
  zlib-dev \
  curl \
  wget \
  icu-dev \
  linux-headers \
  bison \
  flex \
  perl

# Add a non-root user and set permissions
RUN addgroup -S postgres && adduser -S postgres -G postgres

# Install PostgreSQL 16 from source
RUN wget https://ftp.postgresql.org/pub/source/v16.3/postgresql-16.3.tar.gz && \
  tar -xzf postgresql-16.3.tar.gz && \
  cd postgresql-16.3 && \
  ./configure --prefix=/usr/local/pgsql16 && \
  make && make install && \
  cd .. && rm -rf postgresql-16.3*

# Install PostgreSQL 17 from source
RUN wget https://ftp.postgresql.org/pub/source/v17beta1/postgresql-17beta1.tar.gz && \
  tar -xzf postgresql-17beta1.tar.gz && \
  cd postgresql-17beta1 && \
  ./configure --prefix=/usr/local/pgsql17 && \
  make && make install && \
  cd .. && rm -rf postgresql-17beta1*

# Add PostgreSQL binaries to PATH
ENV PATH="/usr/local/pgsql16/bin:/usr/local/pgsql17/bin:$PATH"

# Set ownership of PostgreSQL directories
RUN mkdir -p /var/lib/postgresql/16/data /var/lib/postgresql/17/data && \
  chown -R postgres:postgres /var/lib/postgresql

# Create a script to run pg_upgrade
COPY pg_upgrade.sh /usr/local/bin/pg_upgrade.sh
RUN chmod +x /usr/local/bin/pg_upgrade.sh && chown postgres:postgres /usr/local/bin/pg_upgrade.sh

# Set the default user to postgres
USER postgres

# Set the default command to run pg_upgrade script
CMD ["/usr/local/bin/pg_upgrade.sh"]
