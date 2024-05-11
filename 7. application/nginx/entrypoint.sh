#!/bin/bash

DEFAULT_HTTP_X_FORWARDED_FOR='$http_x_forwarded_for'

# Check if FORCES_IP is set (for geoip testing at local environments)
if [ "$FORCES_IP" = true ]; then
  # If not set, fetch the IP address from the API
  SOURCE_IP=$(curl -s https://api64.ipify.org/)
fi

# If still empty, set the default value
if [ -z "$SOURCE_IP" ]; then
  SOURCE_IP="$DEFAULT_HTTP_X_FORWARDED_FOR"
else
  echo "Initializing with fixed ip: $SOURCE_IP"
fi

export SOURCE_IP

find /etc/nginx -type f -name "*.template" | while read -r template_file; do
  echo "Processing file $template_file"
  envsubst '$STATIC_SERVICE,$STATIC_PROXY_HOST_HEADER,$SOURCE_IP' < "$template_file" > "${template_file%.template}"
done

nginx -t

# Start Nginx
exec nginx -g "daemon off;"