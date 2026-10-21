# User Documentation

This document explains, in simple terms, how to use and administer the Inception stack. Replace `rcarpio-` with the login if it differs.

## 1. Services provided by the stack

| Service | What it does |
|---|---|
| **nginx** | Receives all web traffic on port **443** (HTTPS, TLS 1.2 / 1.3) and forwards it to WordPress. It is the only service reachable from outside. |
| **WordPress (php-fpm)** | Runs the website and its administration panel. |
| **MariaDB** | Stores the WordPress content: posts, pages, comments and users. |

Website data is persistent: stopping or restarting the stack does not delete it.

## 2. Start and stop the project

All commands are run from the root of the repository (where the `Makefile` is).

| Action | Command |
|---|---|
| Start everything (build the images if needed) | `make` |
| Stop and remove the containers (data is kept) | `make down` |
| Stop the containers without removing them | `make stop` |
| Start stopped containers again | `make start` |
| Show the state of the containers | `make status` |
| Follow the logs | `make logs` |

> `make fclean` and `make re` **delete all data** (database and website files). Use them only to start from scratch.

### Before the first start

1. The domain name must point to the machine. In `/etc/hosts` there must be this line:
   ```
   127.0.0.1   rcarpio-.42.fr
   ```
2. The `secrets/` folder must exist with its four files (see section 4).

## 3. Access the website and the administration panel

- **Website:** https://rcarpio-.42.fr
- **Administration panel:** https://rcarpio-.42.fr/wp-login.php

On the first visit the browser warns that the connection is not private, because the TLS certificate is self-signed. This is expected: accept the warning and continue.

Port 80 (plain HTTP) is closed on purpose; always use `https://`.

The stack has two WordPress accounts:

- an **administrator** account, which gives access to the dashboard (create and edit pages, manage users, etc.);
- a regular **author** account, which can write posts and comment.

## 4. Locate and manage credentials

Credentials are split into two places and are never stored in Git.

| What | Where |
|---|---|
| Non-sensitive settings: domain name, database name and user, WordPress usernames and emails | `srcs/.env` |
| Passwords | `secrets/` folder, one file per password |

Files in `secrets/`:

| File | Contains |
|---|---|
| `db_password.txt` | Password of the WordPress database user |
| `db_root_password.txt` | Password of the MariaDB root user |
| `wp_admin_password.txt` | Password of the WordPress administrator |
| `wp_user_password.txt` | Password of the regular WordPress user |

To see which usernames exist: `grep WP_ srcs/.env`.
To read a password: `cat secrets/wp_admin_password.txt`.

### Changing a password

Passwords are stored in the database the **first time** the stack starts, so editing a file in `secrets/` afterwards does not change the existing accounts.

- **WordPress users:** change the password from the WordPress dashboard (Users → Profile).
- **Starting from scratch with new passwords:** edit the files in `secrets/`, then run `make fclean` followed by `make`. **This erases all site data.**

Keep the `secrets/` folder private and never commit it to Git (it is listed in `.gitignore`).

## 5. Check that the services are running correctly

**1. Containers are up**

```bash
docker ps
```

`nginx`, `wordpress` and `mariadb` must appear with the status `Up` (and `healthy` for `mariadb`).

**2. The website answers over HTTPS**

```bash
curl -kI https://rcarpio-.42.fr
```

The first line should be `HTTP/1.1 200 OK` (or a `302` redirect).

**3. Plain HTTP is closed**

```bash
curl -I http://rcarpio-.42.fr
```

This must fail with "connection refused".

**4. The WordPress users exist**

```bash
docker exec wordpress wp user list --allow-root --path=/var/www/html
```

**5. Logs of a service** (if something looks wrong)

```bash
docker logs nginx
docker logs wordpress
docker logs mariadb
```

### Quick troubleshooting

| Problem | What to try |
|---|---|
| The browser cannot find `rcarpio-.42.fr` | Check the line in `/etc/hosts`. |
| "Connection refused" on the site | Run `make status`; if the containers are stopped, run `make`. |
| 502 Bad Gateway | The `wordpress` container is not running: check `docker logs wordpress`. |
| "Error establishing a database connection" | MariaDB is not ready or its passwords changed: check `docker logs mariadb`; to reset, `make fclean` then `make`. |
| Cannot log in | Check the username in `srcs/.env` and the password in `secrets/`. |
