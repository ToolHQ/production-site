FROM docker.elastic.co/logstash/logstash:8.17.1
RUN logstash-plugin install logstash-filter-json_encode
COPY ./patterns /usr/share/logstash/custom_patterns
