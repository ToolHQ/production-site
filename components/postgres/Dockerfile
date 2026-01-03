# syntax=docker/dockerfile:1
FROM postgres:18.1-alpine3.22
COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY entrypoint-wrapper.sh /usr/local/bin/entrypoint-wrapper.sh
RUN chmod +x /usr/local/bin/entrypoint-wrapper.sh
EXPOSE 5432
ENTRYPOINT ["/usr/local/bin/entrypoint-wrapper.sh"]
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]