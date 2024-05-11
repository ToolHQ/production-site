#!/bin/bash

DEFAULT_SOURCE_IP='$http_x_forwarded_for'
DEFAULT_DNS_RESOLVER=127.0.0.11

# Check if FORCES_IP is set (for geoip testing at local environments)
if [ "$FORCES_IP" = true ]; then
  # If not set, fetch the IP address from the API
  SOURCE_IP=$(curl -s https://api64.ipify.org/)
fi

# If still empty, set the default value
if [ -z "$SOURCE_IP" ]; then
  SOURCE_IP="$DEFAULT_SOURCE_IP"
else
  echo "Initializing with fixed ip: $SOURCE_IP"
fi

export SOURCE_IP

if [ -z "$SOURCE_IP" ]; then
  DNS_RESOLVER="$DEFAULT_DNS_RESOLVER"
fi
echo "Initializing with DNS Resolver: $DNS_RESOLVER"

find /etc/nginx -type f -name "*.template" | while read -r template_file; do
  echo "Processing file $template_file"
  envsubst '$STATIC_SERVICE,$STATIC_PROXY_HOST_HEADER,$SOURCE_IP,$DNS_RESOLVER' < "$template_file" > "${template_file%.template}"
done

nginx -t

# Start Nginx
exec nginx -g "daemon off;"