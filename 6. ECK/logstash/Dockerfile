FROM docker.elastic.co/logstash/logstash:8.13.3
RUN logstash-plugin install logstash-filter-json_encode
COPY ./patterns /usr/share/logstash/custom_patterns
