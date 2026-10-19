#!/bin/bash
set -e

mkdir -p /etc/nginx/ssl

# Certificado autofirmado (solo si no existe)
if [ ! -f /etc/nginx/ssl/inception.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/inception.key \
        -out /etc/nginx/ssl/inception.crt \
        -subj "/C=ES/ST=Madrid/L=Madrid/O=42/OU=42/CN=${DOMAIN_NAME}"
fi

# Sustituir el dominio en la configuración
sed -i "s/DOMAIN_PLACEHOLDER/${DOMAIN_NAME}/g" /etc/nginx/conf.d/site.conf

# exec: nginx en primer plano y como PID 1
exec nginx -g "daemon off;"