FROM confluentinc/cp-kafka:7.9.1

# Remove the "dub ensure CLUSTER_ID" blocker
RUN sed -i '/dub ensure CLUSTER_ID/d' /etc/confluent/docker/run
