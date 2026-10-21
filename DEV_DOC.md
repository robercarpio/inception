# Developer Documentation

This document describes how to set up, build, run, debug and maintain the Inception project. Replace `rcarpio-` with your own login where needed.

## 1. Prerequisites

- A **virtual machine** (the project must run inside one) with Linux. Debian was used for development.
- **Docker Engine in rootful mode.** Rootless Docker cannot publish the privileged port 443 and `make` will fail with `cannot expose privileged port 443`. Check with:
  ```bash
  docker info | grep -i rootless      # must print nothing
  docker run --rm -p 443:80 debian:bookworm true
  ```
- **Docker Compose plugin** (`docker compose version`), **make** and **git**.
- Your user must belong to the `docker` group (`sudo usermod -aG docker $USER`, then log out and in).
- Internet access from the VM (the build downloads Debian packages, WP-CLI and WordPress).

## 2. Set up the environment from scratch

### 2.1 Clone the repository

```bash
git clone <repository-url> inception
cd inception
```

### 2.2 Domain name

```bash
echo "127.0.0.1 rcarpio-.42.fr" | sudo tee -a /etc/hosts
```

### 2.3 Configuration file `srcs/.env`

Non-sensitive variables, passed to the containers with `env_file`:

| Variable | Used by | Meaning |
|---|---|---|
| `LOGIN` | compose, Makefile | Login; builds the host data path `/home/${LOGIN}/data` |
| `DOMAIN_NAME` | nginx, wordpress | Domain served by nginx (`<login>.42.fr`) and WordPress URL |
| `MYSQL_DATABASE` | mariadb, wordpress | WordPress database name |
| `MYSQL_USER` | mariadb, wordpress | Database user for WordPress |
| `WP_TITLE` | wordpress | Site title |
| `WP_ADMIN_USER` | wordpress | Administrator username (must **not** contain "admin"/"administrator", in any case) |
| `WP_ADMIN_EMAIL` | wordpress | Administrator email |
| `WP_USER` | wordpress | Second (author) user |
| `WP_USER_EMAIL` | wordpress | Email of the second user |

`.env` must **not** contain passwords.

### 2.4 Secrets

Secrets are **not** in the repository (`secrets/` is in `.gitignore`). Create them by hand:

```bash
mkdir -p secrets
echo "<db user password>"  > secrets/db_password.txt
echo "<db root password>"  > secrets/db_root_password.txt
echo "<wp admin password>" > secrets/wp_admin_password.txt
echo "<wp user password>"  > secrets/wp_user_password.txt
chmod 600 secrets/*.txt
```

They are declared in `srcs/docker-compose.yml` under `secrets:` (`file: ../secrets/<name>.txt`) and mounted in the containers as `/run/secrets/<name>`:

| Secret | Mounted in |
|---|---|
| `db_password` | mariadb, wordpress |
| `db_root_password` | mariadb |
| `wp_admin_password` | wordpress |
| `wp_user_password` | wordpress |

Before committing, always check that nothing sensitive is tracked:

```bash
git status
git ls-files | grep -i secret     # must print nothing
```

### 2.5 Data directories

The `Makefile` creates them automatically, but they can be created by hand:

```bash
mkdir -p /home/rcarpio-/data/mariadb /home/rcarpio-/data/wordpress
```

## 3. Project layout

```
.
├── Makefile
├── secrets/                          # local only, ignored by Git
└── srcs/
    ├── docker-compose.yml
    ├── .env
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/99-custom.cnf    # bind-address 0.0.0.0, port, datadir
        │   └── tools/init.sh         # first-run SQL setup, then exec mysqld
        ├── wordpress/
        │   ├── Dockerfile            # php8.2-fpm, WP-CLI, listen = 9000
        │   └── tools/init.sh         # WP-CLI install, then exec php-fpm8.2 -F
        └── nginx/
            ├── Dockerfile
            ├── conf/site.conf        # TLS 1.2/1.3, FastCGI to wordpress:9000
            └── tools/init.sh         # self-signed cert, then exec nginx
```

Key points about the images:

- All three are built from `debian:bookworm` (penultimate stable Debian when the project was written; check https://www.debian.org/releases/ and update the tag if needed). `latest` is never used.
- Each image is tagged with its service name: `mariadb:inception`, `wordpress:inception`, `nginx:inception`.
- Every entrypoint script ends with `exec <service in foreground>` so the service is PID 1. No infinite loops, `tail -f` or background processes.
- MariaDB configuration file must end in `.cnf` or MariaDB ignores it.

## 4. Build and launch

### With the Makefile (recommended)

```bash
make
```

This creates the data directories and runs `docker compose -f srcs/docker-compose.yml up -d --build`. Using `-f srcs/docker-compose.yml` makes Compose read `srcs/.env` automatically for variable interpolation (`${LOGIN}`).

| Target | What it does |
|---|---|
| `make` / `make up` | Create data dirs, build the images, start the stack in the background |
| `make down` | `docker compose down` (removes containers and network, keeps volumes and data) |
| `make stop` / `make start` | Stop / start the existing containers |
| `make logs` | `docker compose logs -f` |
| `make status` | `docker compose ps` |
| `make clean` | `down` + `docker system prune -af` |
| `make fclean` | `down -v --rmi all`, prune everything, delete `/home/<login>/data/*` (uses `sudo`) |
| `make re` | `fclean` + `all` |

> `clean` and `fclean` run `docker system prune -af`, which removes **all** unused Docker images and containers on the machine, not only this project.

### With Docker Compose directly

```bash
docker compose -f srcs/docker-compose.yml up -d --build
docker compose -f srcs/docker-compose.yml down
docker compose -f srcs/docker-compose.yml ps
```

or from inside `srcs/`:

```bash
cd srcs && docker compose up -d --build
```

### Start-up sequence

1. `mariadb` starts, initialises its data directory and creates the database and user on first run, then runs `mysqld` in the foreground. Its `healthcheck` (`mysqladmin ping`) turns `healthy`.
2. `wordpress` starts once MariaDB is `healthy` (`depends_on: condition: service_healthy`). On first run it downloads WordPress, creates `wp-config.php`, installs the site and creates both users with WP-CLI, then runs `php-fpm8.2 -F`.
3. `nginx` starts after `wordpress`, generates a self-signed certificate if needed, and serves HTTPS on 443.

## 5. Managing containers and volumes

### Containers

```bash
docker ps                                   # running containers
docker compose -f srcs/docker-compose.yml ps
docker logs <mariadb|wordpress|nginx>       # service logs
docker exec -it mariadb bash                # shell inside a container (debugging only)
docker top nginx                            # processes; PID 1 must be the service
docker inspect <container>                  # configuration, mounts, networks
docker compose -f srcs/docker-compose.yml config   # compose file with variables resolved
docker restart <container>
```

Simulate a crash and check the restart policy (`docker stop` does not trigger `unless-stopped`):

```bash
docker kill nginx && sleep 5 && docker ps
```

### Database

```bash
docker exec -it mariadb mysql -u root -p          # asks for the root password (secrets/db_root_password.txt)
```
```sql
SHOW DATABASES;
USE wordpress;
SHOW TABLES;
SELECT user_login FROM wp_users;
```

### WordPress

```bash
docker exec wordpress wp user list --allow-root --path=/var/www/html
docker exec wordpress wp plugin list --allow-root --path=/var/www/html
```

### Network

```bash
docker network ls                    # srcs_inception
docker network inspect srcs_inception
```

### Volumes

```bash
docker volume ls                              # srcs_mariadb_data, srcs_wordpress_data
docker volume inspect srcs_mariadb_data       # "device" must be /home/rcarpio-/data/mariadb
docker volume inspect srcs_wordpress_data     # "device" must be /home/rcarpio-/data/wordpress
ls /home/rcarpio-/data/mariadb /home/rcarpio-/data/wordpress
```

### Images

```bash
docker images        # mariadb:inception, wordpress:inception, nginx:inception
docker history nginx:inception
```

## 6. Where data is stored and how it persists

| Data | Container path | Volume | Host path |
|---|---|---|---|
| MariaDB database | `/var/lib/mysql` | `srcs_mariadb_data` | `/home/rcarpio-/data/mariadb` |
| WordPress files (core, themes, plugins, uploads) | `/var/www/html` | `srcs_wordpress_data` | `/home/rcarpio-/data/wordpress` |

The `wordpress_data` volume is mounted in both `wordpress` (read/write) and `nginx` (read-only), so nginx can serve static files directly.

Both are Docker **named volumes** declared with the `local` driver and `driver_opts` (`type: none`, `o: bind`, `device: /home/${LOGIN}/data/...`). This keeps them as named volumes while placing the data at the host path required by the subject.

Persistence behaviour:

- `make down`, `make stop`, a container crash or a VM reboot **keep** the data, because it lives on the host and not in the containers.
- On restart the entrypoint scripts detect the existing data and skip the initialisation (database creation, WordPress installation), so nothing is overwritten.
- `make fclean` / `make re` **delete** the volumes and the contents of `/home/<login>/data`.
- Passwords and usernames are written into MariaDB on the first start only. If you change `secrets/` or `.env` afterwards, run `make fclean` then `make` for the change to take effect.

## 7. Modifying the configuration

Common changes and what they involve:

| Change | Files to update | Then |
|---|---|---|
| nginx listening port | `srcs/requirements/nginx/conf/site.conf` (`listen`), `ports:` in `docker-compose.yml`, `EXPOSE` in the Dockerfile | `make down && make` |
| MariaDB port | `conf/99-custom.cnf` (`port`), `--dbhost=mariadb:<port>` in the wordpress `init.sh` | `make fclean && make` if data was already initialised |
| php-fpm port | `sed` of `listen = 9000` in the wordpress Dockerfile, `fastcgi_pass wordpress:<port>` in `site.conf` | `make down && make` |
| Domain name | `DOMAIN_NAME` in `.env`, `/etc/hosts` | `make fclean && make` (WordPress stores the URL on install) |
| New environment variable | `srcs/.env`, then read it in the relevant `init.sh` | `make down && make` |

Images are rebuilt by `make` thanks to `--build`; Docker reuses cached layers, so only the changed steps are rebuilt. Use `docker compose -f srcs/docker-compose.yml build --no-cache <service>` to force a clean build.

## 8. Verification checklist

```bash
# Rules
grep -rn -E "tail -f|sleep infinity|while true" srcs/ Makefile        # nothing
grep -rn -E "network_mode|links:|--link" srcs/ Makefile              # nothing
grep -n "^FROM" srcs/requirements/*/Dockerfile                        # debian:bookworm, no latest
grep -rni "password" srcs/requirements/*/Dockerfile                   # no real passwords
git ls-files | grep -i secret                                         # nothing

# Runtime
curl -kI https://rcarpio-.42.fr                                       # 200 / 302
curl -I http://rcarpio-.42.fr                                         # must fail (port 80 closed)
openssl s_client -connect rcarpio-.42.fr:443 -tls1_2 </dev/null | grep -i protocol
openssl s_client -connect rcarpio-.42.fr:443 -tls1_3 </dev/null | grep -i protocol
openssl s_client -connect rcarpio-.42.fr:443 -tls1_1 </dev/null       # must fail
```

Also verify: two WordPress users exist, the administrator name does not contain "admin", content survives `make down && make` and a VM reboot, and the containers come back after `docker kill`.

## 9. Known pitfalls

- **Rootless Docker** (e.g. on a shared workstation) cannot bind port 443. Work inside the VM with rootful Docker.
- **Makefile recipes must be indented with TAB characters**, not spaces.
- **MariaDB config must be named `*.cnf`**; any other extension is ignored.
- **Secrets accidentally tracked by Git**: `.gitignore` does not untrack files already committed. Use `git rm -r --cached secrets/`, and rewrite the history if they were ever pushed.
- **Stale data after a failed first run**: the database may be initialised with old credentials. Run `make fclean` and retry.
- **Windows/CRLF line endings** in `init.sh` break the shebang (`/bin/bash^M`). Keep scripts with LF endings.
