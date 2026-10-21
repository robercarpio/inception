*This project has been created as part of the 42 curriculum by rcarpio-.*

# Inception

## Description

Inception is a System Administration project whose goal is to broaden knowledge of containerization by building a small, self-contained web infrastructure with **Docker** and **Docker Compose**, entirely inside a virtual machine.

The stack is composed of three services, each running in its own dedicated container and built from our own Dockerfiles (no ready-made images are pulled; only the base `debian:bookworm` image is used):

| Service | Role | Exposed to the host |
|---|---|---|
| **nginx** | Reverse proxy / web server, TLS 1.2 and TLS 1.3 only | Port **443** (the only entrypoint) |
| **wordpress** | WordPress + PHP-FPM (installed and configured with WP-CLI), without nginx | None (port 9000 inside the Docker network) |
| **mariadb** | MariaDB database server, without nginx | None (port 3306 inside the Docker network) |

Two persistent **named volumes** store the WordPress database and the WordPress website files, both physically located under `/home/rcarpio-/data` on the host. A user-defined Docker **bridge network** connects the containers, and all containers restart automatically if they crash.

```
                 Browser / WWW
                       │  443 (TLS 1.2 / 1.3)
            ┌──────────▼───────────┐
            │     Docker network   │
            │  ┌────────────────┐  │
            │  │     nginx      │  │
            │  └───────┬────────┘  │
            │          │ 9000 (FastCGI)
            │  ┌───────▼────────┐  │
            │  │   wordpress    │──┼──► volume: WordPress files
            │  │   (php-fpm)    │  │
            │  └───────┬────────┘  │
            │          │ 3306      │
            │  ┌───────▼────────┐  │
            │  │    mariadb     │──┼──► volume: database
            │  └────────────────┘  │
            └──────────────────────┘
```

## Instructions

### Prerequisites

- A **virtual machine** running Linux (this project was developed on Debian) with a **rootful** Docker installation (rootless Docker cannot publish the privileged port 443).
- `docker`, `docker compose` (plugin), `make` and `git`.
- Your user must be able to run Docker (member of the `docker` group).

### Setup

1. Clone the repository in an empty directory:
   ```bash
   git clone <repository-url> inception && cd inception
   ```
2. Point the domain name to the local machine:
   ```bash
   echo "127.0.0.1 rcarpio-.42.fr" | sudo tee -a /etc/hosts
   ```
3. Create the secrets (they are **not** stored in Git). Create one file per secret in `secrets/`, each containing only the password:
   ```bash
   mkdir -p secrets
   echo "<db user password>"   > secrets/db_password.txt
   echo "<db root password>"   > secrets/db_root_password.txt
   echo "<wp admin password>"  > secrets/wp_admin_password.txt
   echo "<wp user password>"   > secrets/wp_user_password.txt
   chmod 600 secrets/*.txt
   ```
4. Review `srcs/.env` (domain name, database name and user, WordPress usernames and emails). It contains **no passwords**.

### Build and run

```bash
make          # create data directories, build the images and start the stack
make down     # stop and remove the containers (data is kept)
make stop     # stop the containers without removing them
make start    # start stopped containers
make logs     # follow the logs of all services
make status   # list the containers
make re       # full clean (fclean) followed by a fresh build
make fclean   # remove containers, images, volumes and the data in /home/rcarpio-/data
```

### Access

- Website: `https://rcarpio-.42.fr`
- Administration panel: `https://rcarpio-.42.fr/wp-login.php`

The TLS certificate is self-signed, so the browser shows a warning that has to be accepted. Port 80 is intentionally closed.

More details are available in [`USER_DOC.md`](USER_DOC.md) (end user / administrator) and [`DEV_DOC.md`](DEV_DOC.md) (developer).

## Project description

### Use of Docker and sources included in the project

All configuration lives in the `srcs/` directory, and the `Makefile` at the root drives `docker compose`:

```
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/                 # local only, ignored by Git
│   ├── db_password.txt
│   ├── db_root_password.txt
│   ├── wp_admin_password.txt
│   └── wp_user_password.txt
└── srcs/
    ├── docker-compose.yml
    ├── .env
    └── requirements/
        ├── mariadb/   (Dockerfile, .dockerignore, conf/, tools/)
        ├── wordpress/ (Dockerfile, .dockerignore, conf/, tools/)
        └── nginx/     (Dockerfile, .dockerignore, conf/, tools/)
```

- **One Dockerfile per service**, built from `debian:bookworm` (the penultimate stable Debian release at the time of writing). The `latest` tag is never used, and the resulting images are named like their service (`nginx:inception`, `wordpress:inception`, `mariadb:inception`).
- **Entrypoint scripts** (`tools/init.sh`) perform the first-run initialisation (database and users for MariaDB, WordPress download and installation with WP-CLI, self-signed certificate generation for nginx) and finish with `exec`, so that the real service (`mysqld`, `php-fpm8.2 -F`, `nginx -g "daemon off;"`) runs in the foreground as **PID 1**. No `tail -f`, `sleep infinity`, infinite loops or background processes are used.
- **Start-up order**: MariaDB exposes a `healthcheck`; WordPress waits for it with `depends_on: condition: service_healthy`, and nginx starts after WordPress.
- **Restart policy**: `restart: unless-stopped` on every service.
- **Configuration**: non-sensitive values in `srcs/.env`, sensitive values as Docker secrets read from `/run/secrets/*` inside the containers.
- **WordPress users**: two users are created, an administrator (whose name does not contain "admin" or "administrator") and a regular `author` user.

### Main design choices

- **Debian over Alpine**: familiarity and a predictable package set (`php8.2-fpm`, `mariadb-server`, `nginx` from the official Debian repositories).
- **WP-CLI** automates the WordPress installation so that the site is ready on first start (no installation wizard).
- **FastCGI over the Docker network**: nginx forwards `.php` requests to `wordpress:9000`, and PHP-FPM listens on TCP instead of a Unix socket so it is reachable from another container.
- **Idempotent initialisation**: scripts check whether data already exists, so restarting containers never re-initialises or overwrites persisted data.
- **A single entrypoint**: only nginx publishes a port (443). MariaDB and WordPress are reachable only from inside the Docker network.
- **Self-signed certificate** restricted to TLS 1.2 and TLS 1.3, generated at container start with the domain from `.env`.

### Virtual Machines vs Docker

| | Virtual Machine | Docker |
|---|---|---|
| Isolation | Full hardware virtualisation, each VM has its own kernel | Process-level isolation (namespaces, cgroups) sharing the host kernel |
| Weight | Gigabytes, minutes to boot | Megabytes, seconds to start |
| Resources | Reserved per VM | Shared and used on demand |
| Portability | Large disk images | Small, layered images defined by a Dockerfile |
| Security boundary | Stronger | Weaker, since the kernel is shared |

Docker is used here to run each service in a lightweight, reproducible environment, while a VM is still required as the host that contains the whole project.

### Secrets vs Environment Variables

| | Environment variables | Docker secrets |
|---|---|---|
| Storage | Part of the container configuration | Files mounted in `/run/secrets/<name>` |
| Visibility | Visible with `docker inspect` and in the process environment | Not shown by `docker inspect` |
| Typical use | Non-sensitive configuration (domain, usernames, database name) | Passwords and credentials |

This project keeps non-sensitive data in `srcs/.env` and passwords in `secrets/*.txt`, which are ignored by Git and read by the entrypoint scripts at runtime. No password appears in any Dockerfile or in the repository.

### Docker Network vs Host Network

| | Docker (bridge) network | Host network |
|---|---|---|
| Isolation | Containers get their own network namespace and private IPs | The container shares the host network stack |
| Name resolution | Built-in DNS: containers reach each other by service name (`mariadb`, `wordpress`) | None |
| Port exposure | Only explicitly published ports are reachable | Every listening port is exposed on the host |

A user-defined bridge network (`inception`) is used. `network: host`, `links:` and `--link` are forbidden by the subject and would remove the isolation between services.

### Docker Volumes vs Bind Mounts

| | Named volume | Bind mount |
|---|---|---|
| Managed by | Docker (declared in `volumes:`) | The user, by directly mapping a host path |
| Portability | Independent of the host directory layout | Depends on an existing host path |
| Permissions / lifecycle | Handled by Docker, visible with `docker volume ls` | Handled manually |

The subject requires **named volumes** whose data lives in `/home/rcarpio-/data`. They are declared with the `local` driver and `driver_opts` (`type: none`, `o: bind`, `device: /home/rcarpio-/data/...`), so they remain real Docker named volumes while storing their data at the required host location. Plain bind mounts in the services are not used.

## Resources

### References

- Docker documentation: https://docs.docker.com/
- Dockerfile best practices: https://docs.docker.com/build/building/best-practices/
- Docker Compose file reference: https://docs.docker.com/reference/compose-file/
- Docker secrets in Compose: https://docs.docker.com/compose/how-tos/use-secrets/
- Docker volumes and bind mounts: https://docs.docker.com/engine/storage/
- NGINX documentation: https://nginx.org/en/docs/
- NGINX `ngx_http_ssl_module`: https://nginx.org/en/docs/http/ngx_http_ssl_module.html
- MariaDB Knowledge Base: https://mariadb.com/kb/en/
- WordPress documentation: https://wordpress.org/documentation/
- WP-CLI handbook: https://make.wordpress.org/cli/handbook/
- PHP-FPM manual: https://www.php.net/manual/en/install.fpm.php
- Debian releases: https://www.debian.org/releases/

### Use of AI

An AI assistant (Claude) was used as a learning and support tool, not as a replacement for understanding. It was used for:

- **Planning**: breaking the subject down into steps and building the directory structure.
- **Drafting**: a first version of the Dockerfiles, the entrypoint scripts (`init.sh` of MariaDB, WordPress and nginx), `docker-compose.yml`, the `Makefile` and the nginx configuration.
- **Debugging**: interpreting build and runtime errors (misnamed configuration file, rootless Docker not allowed to publish port 443, secrets mistakenly tracked by Git).
- **Documentation**: structuring this README, `USER_DOC.md` and `DEV_DOC.md`, and preparing the evaluation checklist.

Everything generated was reviewed, tested in the virtual machine and understood before being kept, and the author can explain every line of the configuration.
