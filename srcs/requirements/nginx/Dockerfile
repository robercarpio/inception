FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx openssl \
    && rm -rf /var/lib/apt/lists/*

# Quitar el sitio por defecto (escucha en el puerto 80)
RUN rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf

COPY conf/site.conf /etc/nginx/conf.d/site.conf
COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/init.sh"]