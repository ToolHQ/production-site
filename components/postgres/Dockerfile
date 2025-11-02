# syntax=docker/dockerfile:1
FROM postgres:18.0-alpine3.22
COPY postgresql.conf /etc/postgresql/postgresql.conf
EXPOSE 5432
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]