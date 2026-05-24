FROM nginx:alpine-slim

# Copy the static web application files to Nginx default public directory
COPY index.html /usr/share/nginx/html/
COPY style.css /usr/share/nginx/html/
COPY game.js /usr/share/nginx/html/

# Expose default HTTP port
EXPOSE 80

# Run nginx in foreground
CMD ["nginx", "-g", "daemon off;"]
