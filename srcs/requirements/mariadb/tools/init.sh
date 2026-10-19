#!/bin/bash
set -e

# Las contraseñas llegan como ficheros (Docker secrets), NO escritas aquí
DB_PASSWORD="$(cat /run/secrets/db_password)"
DB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"

# Directorios necesarios y permisos (el volumen llega montado como root)
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld /var/lib/mysql

# Inicializar el directorio de datos solo si está vacío (primer arranque)
if [ ! -d /var/lib/mysql/mysql ]; then
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null
fi

# Crear BBDD y usuarios solo la primera vez
if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    mysqld --user=mysql --bootstrap << EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF
fi

# exec: mysqld pasa a ser PID 1 y corre en primer plano
exec mysqld --user=mysql