# syntax=docker/dockerfile:1
FROM postgres:16.6-alpine3.21
# FROM postgres:17beta1-alpine3.20
COPY postgresql.conf /etc/postgresql/postgresql.conf
EXPOSE 5432
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]