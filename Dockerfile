# Inkognito: privacy-first LinkedIn formatter, served by lighttpd on Alpine.
# docker build -t inkognito . && docker run -d --name inkognito -p 8080:8080 --read-only --tmpfs /tmp inkognito
FROM alpine:3
RUN apk add --no-cache lighttpd \
 && mkdir -p /var/www/inkognito \
 && adduser -D -H -u 10001 inkognito
COPY docker/lighttpd.conf /etc/lighttpd/lighttpd.conf
COPY --chmod=644 inkognito.html /var/www/inkognito/index.html
USER inkognito
EXPOSE 8080
HEALTHCHECK --interval=60s --timeout=3s CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/lighttpd.conf"]
