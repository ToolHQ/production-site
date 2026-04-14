FROM golang:1.22.3-alpine3.19 AS base
ENV GEOIPUPDATE_VERSION=7.1.0
RUN go install github.com/maxmind/geoipupdate/v7/cmd/geoipupdate@v${GEOIPUPDATE_VERSION}

# Based on https://github.com/bubelov/nginx-alpine-geoip2/blob/master/Dockerfile
FROM alpine:3.19.1

ENV MAXMIND_VERSION=1.9.1
ENV HEADERS_MORE_VERSION=0.37
ENV NGINX_VERSION=1.26.0
ENV GEOLITE_DATE=20240510

WORKDIR /tmp

RUN set -x \
  && apk add --no-cache --virtual .build-deps \
    alpine-sdk \
    perl \
  && git clone https://github.com/leev/ngx_http_geoip2_module ./ngx_http_geoip2_module \
  && wget https://github.com/maxmind/libmaxminddb/releases/download/${MAXMIND_VERSION}/libmaxminddb-${MAXMIND_VERSION}.tar.gz -O libmaxminddb.tar.gz \
  && wget https://github.com/openresty/headers-more-nginx-module/archive/v${HEADERS_MORE_VERSION}.tar.gz -O headers-more-nginx-module.tar.gz \
  && mkdir libmaxminddb && tar xf libmaxminddb.tar.gz -C libmaxminddb --strip-components 1 \
  && mkdir headers-more-nginx-module && tar xf headers-more-nginx-module.tar.gz -C headers-more-nginx-module --strip-components 1 \
  && rm libmaxminddb.tar.gz \
  && rm headers-more-nginx-module.tar.gz \
  && cd libmaxminddb \
  && ./configure \
  && make \
  && make check \
  && make install \
  && apk del .build-deps \
  && rm -rf ../libmaxminddb

RUN ldconfig || :

# At this step libmaxminddb is installed and sources for modules are at: /tmp/headers-more-nginx-module /tmp/ngx_http_geoip2_module

# Todo: Investigate correct installation for --with-http_v3_module, --with-http_image_filter_module=dynamic
# Discarted: --with-http_xslt_module=dynamic, --with-http_dav_module, --with-http_flv_module, --with-http_random_index_module, --with-http_secure_link_module, --with-http_slice_module, --with-http_perl_module=dynamic, --with-perl_modules_path=path, --with-perl=path, --with-mail=dynamic, --with-mail_ssl_module, --with-google_perftools_module
# May be discarted in the future if no use: --with-http_addition_module, --with-http_image_filter_module=dynamic, --with-http_mp4_module

# Install nginx
RUN CONFIGURE_OPTIONS="\
  --prefix=/etc/nginx \
  --sbin-path=/usr/sbin/nginx \
  --modules-path=/usr/lib/nginx/modules \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/var/run/nginx.pid \
  --lock-path=/var/run/nginx.lock \
  --http-client-body-temp-path=/var/cache/nginx/client_temp \
  --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
  --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
  --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
  --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
  --user=nginx \
  --group=nginx \
  --with-threads \
  --with-file-aio \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-http_realip_module \
  --with-http_addition_module \
  --with-http_image_filter_module=dynamic \
  --with-http_geoip_module=dynamic \
  --with-http_sub_module \
  --with-http_mp4_module \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_auth_request_module \
  --with-http_stub_status_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_realip_module \
  --with-stream_geoip_module=dynamic \
  --with-stream_ssl_preread_module \
  --with-compat \
  --add-dynamic-module=/tmp/ngx_http_geoip2_module \
  --add-dynamic-module=/tmp/headers-more-nginx-module \
  " \
	&& addgroup -S nginx \
	&& adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
	&& apk add --no-cache --virtual .build-deps \
		gcc \
		libc-dev \
		make \
		openssl-dev \
		pcre-dev \
		zlib-dev \
		linux-headers \
		curl \
		libxslt-dev \
		gd-dev \
		geoip-dev \
  && curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz \
  && mkdir -p /usr/src/nginx \
  && tar -xf nginx.tar.gz -C /usr/src/nginx --strip-components 1 \
  && rm nginx.tar.gz \
  && cd /usr/src/nginx \
  && ./configure $CONFIGURE_OPTIONS --with-debug \
  && make -j$(getconf _NPROCESSORS_ONLN) \
  && make install \
  && mv objs/nginx objs/nginx-debug \
  && mv objs/ngx_http_image_filter_module.so objs/ngx_http_image_filter_module-debug.so \
  && mv objs/ngx_http_geoip2_module.so objs/ngx_http_geoip2_module-debug.so \
  && mv objs/ngx_http_geoip_module.so objs/ngx_http_geoip_module-debug.so \
  && mv objs/ngx_http_headers_more_filter_module.so objs/ngx_http_headers_more_filter_module-debug.so \
  && mv objs/ngx_stream_geoip2_module.so objs/ngx_stream_geoip2_module-debug.so \
  && mv objs/ngx_stream_geoip_module.so objs/ngx_stream_geoip_module-debug.so \
  && ./configure $CONFIGURE_OPTIONS \
  && make -j$(getconf _NPROCESSORS_ONLN) \
  && make install \
  && rm -rf /etc/nginx/html/ \
  && mkdir /etc/nginx/conf.d/ \
  && mkdir -p /usr/share/nginx/html/ \
  && install -m644 html/index.html /usr/share/nginx/html/ \
  && install -m644 html/50x.html /usr/share/nginx/html/ \
  && install -m755 objs/nginx-debug /usr/sbin/nginx-debug \
  && install -m755 objs/ngx_http_image_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_image_filter_module-debug.so \
  && install -m755 objs/ngx_http_geoip2_module-debug.so /usr/lib/nginx/modules/ngx_http_geoip2_module-debug.so \
  && install -m755 objs/ngx_http_geoip_module-debug.so /usr/lib/nginx/modules/ngx_http_geoip_module-debug.so \
  && install -m755 objs/ngx_http_headers_more_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_headers_more_filter_module-debug.so \
  && install -m755 objs/ngx_stream_geoip2_module-debug.so /usr/lib/nginx/modules/ngx_stream_geoip2_module-debug.so \
  && install -m755 objs/ngx_stream_geoip_module-debug.so /usr/lib/nginx/modules/ngx_stream_geoip_module-debug.so \
  && ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
  && strip /usr/sbin/nginx* \
  && strip /usr/lib/nginx/modules/*.so \
  && rm -rf /usr/src/nginx \
  \
  # Bring in gettext so we can get `envsubst`, then throw
  # the rest away. To do this, we need to install `gettext`
  # then move `envsubst` out of the way so `gettext` can
  # be deleted completely, then move `envsubst` back.
  && apk add --no-cache --virtual .gettext gettext \
  && mv /usr/bin/envsubst /tmp/ \
  \
  && runDeps="$( \
    scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
      | tr ',' '\n' \
      | sort -u \
      | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  )" \
  && apk add --no-cache --virtual .nginx-rundeps $runDeps \
  && apk del .build-deps \
  && apk del .gettext \
  && mv /tmp/envsubst /usr/local/bin/ \
  \
  # Bring in tzdata so users could set the timezones through the environment
  # variables
  && apk add --no-cache tzdata curl \
  \
  # forward request and error logs to docker log collector
  && ln -sf /dev/stdout /var/log/nginx/access.log \
  && ln -sf /dev/stderr /var/log/nginx/error.log \
  && ln -sf /dev/stdout /var/log/nginx/geoipupdate.log \
  && rm -rf /tmp/headers-more-nginx-module /tmp/ngx_http_geoip2_module

WORKDIR /etc/nginx

COPY --from=base /go/bin/geoipupdate /usr/local/bin/geoipupdate
COPY GeoIP.conf /usr/local/etc/GeoIP.conf
RUN echo "5 * * * * /usr/local/bin/geoipupdate >> /var/log/nginx/geoipupdate.log" > /etc/nginx/GeoIPCron.txt \
  && /usr/bin/crontab /etc/nginx/GeoIPCron.txt \
  && /usr/sbin/crond -l 6
RUN /usr/local/bin/geoipupdate
COPY GeoLite2-ASN_${GEOLITE_DATE}.mmdb /usr/share/geoip/GeoLite2-ASN.mmdb
COPY GeoLite2-City_${GEOLITE_DATE}.mmdb /usr/share/geoip/GeoLite2-City.mmdb
COPY GeoLite2-Country_${GEOLITE_DATE}.mmdb /usr/share/geoip/GeoLite2-Country.mmdb

COPY ./www /data/www/
COPY nginx.conf /etc/nginx/nginx.conf.template
COPY default.conf /etc/nginx/conf.d/default.conf.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["sh", "/usr/local/bin/entrypoint.sh"]
