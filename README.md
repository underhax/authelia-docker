# Hardened Containerized Authelia

[![CI](https://github.com/underhax/authelia-docker/actions/workflows/ci.yml/badge.svg)](https://github.com/underhax/authelia-docker/actions/workflows/ci.yml)
[![GitHub last commit](https://img.shields.io/github/last-commit/underhax/authelia-docker)](https://github.com/underhax/authelia-docker/commits/main)
[![GitHub issues](https://img.shields.io/github/issues/underhax/authelia-docker)](https://github.com/underhax/authelia-docker/issues)
[![GitHub repo size](https://img.shields.io/github/repo-size/underhax/authelia-docker)](https://github.com/underhax/authelia-docker)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Production-grade deployment architecture for [Authelia](https://github.com/authelia/authelia) built on zero-trust principles, least-privilege runtime enforcement, and complete isolation.

## Architecture & Security Model

- Minimal scratch image without a shell or system utilities, containing only the application binary, required runtime libraries, CA certificates, and a custom static health probe.
- Read-only container root filesystem with all Linux capabilities dropped, privilege escalation disabled, and IPC namespace isolated.
- In-memory secret ingestion via Docker Secrets to prevent credential exposure in environment variables or deployment manifests.
- Host Discretionary Access Control enforcement using dedicated unprivileged system user and group identifiers.
- No host port bindings, communicating with edge reverse proxies exclusively through the external frontend gateway network.
- Structured security audit logging to an isolated volume for firewall-level intrusion prevention via CrowdSec.
- Self-contained health monitoring using an embedded static probe without external dependencies.

---

<details>
<summary><strong>Directory Structure</strong></summary>

Production directory layout on the host (`/home/authelia`):

```text
├── docker-compose.yaml                     # Production deployment manifest
├── .env                                    # Host infrastructure configuration
├── config/                                 # Authelia configuration directory
│   ├── configuration.yml                   # Active Authelia configuration
│   └── users_database.yml                  # File-based user database
├── secrets/                                # Docker secrets directory
│   ├── authelia_session_secret             # Secret for session cookies
│   ├── authelia_storage_encryption_key     # SQLite storage encryption key
│   ├── authelia_smtp_address               # SMTP server address (e.g. smtp://mail.example.com:587)
│   ├── authelia_smtp_username              # SMTP relay username
│   ├── authelia_smtp_password              # SMTP relay password
│   ├── authelia_smtp_sender                # Sender address (e.g. Authelia <admin@example.com>)
│   ├── authelia_oidc_hmac_secret           # (Optional) OIDC HMAC secret
│   └── authelia_oidc_jwks_key              # (Optional) OIDC JWKS RSA private key
├── data/                                   # Persistent storage (SQLite database)
│   └── db.sqlite3                          # Encrypted SQLite database file
└── logs/                                   # Service logs directory (monitored by CrowdSec)
    └── authelia.log                        # Active log file (mode 0600)
```

</details>

---

<details>
<summary><strong>Deployment &amp; Setup</strong></summary>

### Prerequisites

* **Docker Engine & Compose:** Ensure Docker Engine and the Docker Compose plugin are installed on the host. Follow the official installation guide for [Ubuntu](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository).
* **External Gateway Network (Optional):** Required only when publishing Authelia externally under a domain name via an [Angie Reverse Proxy](https://github.com/webstudiobond/angie-docker-compose), which automatically provisions the shared `frontend_gateway` network. If deploying standalone without the Angie stack, create it manually:

  ```bash
  docker network create --subnet=172.20.0.0/16 frontend_gateway
  ```

### 1. Create a Dedicated System User

Choose a dedicated, unprivileged numeric ID unique to this service on your host and verify that it is not in use:

```bash
APP_UID=<CHOSEN_UID>

getent passwd ${APP_UID}
getent group ${APP_UID}
```

Create an unprivileged system account with a matching user-group (`-U`) and disabled login shell:

```bash
sudo useradd -M -d /home/authelia -s /usr/sbin/nologin -u ${APP_UID} -U authelia
```

### 2. Create Directory Layout & Assign Ownership

Create the base directory and assign ownership:

```bash
sudo mkdir -p /home/authelia
sudo chown root:authelia /home/authelia
sudo chmod 0750 /home/authelia
```

Create runtime subdirectories and assign strict DAC permissions:

```bash
sudo mkdir -p /home/authelia/{config,data,logs,secrets}

sudo chown root:authelia /home/authelia/{config,secrets}
sudo chmod 0750 /home/authelia/{config,secrets}

sudo chown authelia:authelia /home/authelia/{data,logs}
sudo chmod 0700 /home/authelia/{data,logs}
```

### 3. Deploy Project Files

Download the production manifests into `/home/authelia`:

```bash
REPO="https://raw.githubusercontent.com/underhax/authelia-docker/main"

sudo curl -fsSL ${REPO}/docker-compose.yaml -o /home/authelia/docker-compose.yaml
sudo curl -fsSL ${REPO}/.env.example -o /home/authelia/.env
sudo curl -fsSL ${REPO}/config/configuration.yml.example -o /home/authelia/config/configuration.yml
sudo curl -fsSL ${REPO}/config/users_database.yml.example -o /home/authelia/config/users_database.yml

sudo chown root:root /home/authelia/{docker-compose.yaml,.env}
sudo chmod 0600 /home/authelia/{docker-compose.yaml,.env}

sudo chown root:authelia /home/authelia/config/{configuration.yml,users_database.yml}
sudo chmod 0640 /home/authelia/config/{configuration.yml,users_database.yml}
```

### 4. Configure Host Environment Settings

```bash
sed -i "s/^APP_UID=.*/APP_UID=${APP_UID}/" /home/authelia/.env
sed -i "s/^APP_GID=.*/APP_GID=${APP_UID}/" /home/authelia/.env
```

### 5. Generate Docker Secrets

Initialize secret files and assign strict host permissions:

```bash
sudo touch /home/authelia/secrets/{authelia_session_secret,authelia_storage_encryption_key,authelia_smtp_address,authelia_smtp_username,authelia_smtp_password,authelia_smtp_sender}
sudo chown root:authelia /home/authelia/secrets/*
sudo chmod 0440 /home/authelia/secrets/*
```

Generate session secret (at least 64 characters recommended)

```bash
openssl rand -hex 64 | sudo tee /home/authelia/secrets/authelia_session_secret > /dev/null
```

Generate storage encryption key (at least 64 characters recommended)

```bash
openssl rand -hex 64 | sudo tee /home/authelia/secrets/authelia_storage_encryption_key > /dev/null
```

> **Note:** The `authelia_smtp_address` secret requires the URI format `submissions://<smtp_host>:<smtp_port>`.

```bash
sudo nano /home/authelia/secrets/authelia_smtp_address
sudo nano /home/authelia/secrets/authelia_smtp_username
sudo nano /home/authelia/secrets/authelia_smtp_sender
sudo nano /home/authelia/secrets/authelia_smtp_password
```

### 6. Configure Authelia and User Database

1. **Configure `users_database.yml`:**
   Generate an Argon2id password hash for each user:
   ```bash
   docker run --rm -it ghcr.io/underhax/authelia-docker:latest crypto hash generate argon2
   ```
   Edit the database file:
   ```bash
   sudo nano /home/authelia/config/users_database.yml
   ```
   The default entry serves strictly as a syntax reference and must be updated for production: replace `username` with a unique identifier, set `disabled: false`, define a `displayname`, insert the generated hash into `password`, specify the actual `email`, and assign authorization `groups`. Append additional users using the same schema.

2. **Configure `configuration.yml`:**
   Customize session and access control policies according to the official documentation: [Session Configuration](https://www.authelia.com/configuration/session/introduction/) and [Access Control](https://www.authelia.com/configuration/security/access-control/):
   ```bash
   sudo nano /home/authelia/config/configuration.yml
   ```

3. **Validate Configuration:**
   Verify configuration syntax, template filters, and secret resolutions prior to launching the stack:
   ```bash
   sudo docker run --rm \
     -e X_AUTHELIA_CONFIG_FILTERS=template \
     -v /home/authelia/config:/config:ro \
     -v /home/authelia/secrets:/run/secrets:ro \
     ghcr.io/underhax/authelia-docker:latest \
     config validate --config /config/configuration.yml
   ```

### 7. Configure OpenID Connect (OIDC) (Optional)

When integrating applications via OpenID Connect 1.0, refer to the official [OpenID Connect Documentation](https://www.authelia.com/integration/openid-connect/introduction/):

1. **Generate OIDC Provider Secrets (One-time setup):**
   ```bash
   openssl rand -hex 64 | sudo tee /home/authelia/secrets/authelia_oidc_hmac_secret > /dev/null

   sudo docker run --rm -v /home/authelia/secrets:/secrets ghcr.io/underhax/authelia-docker:latest \
     crypto pair rsa generate --directory /secrets \
     --file.private-key authelia_oidc_jwks_key \
     --file.public-key authelia_oidc_jwks_pub.key

   sudo chown root:authelia /home/authelia/secrets/*
   sudo chmod 0440 /home/authelia/secrets/*
   ```

2. **Generate Client ID & Client Secret Hash (Per application):**
   ```bash
   docker run --rm -it ghcr.io/underhax/authelia-docker:latest crypto rand --length 72 --charset rfc3986

   docker run --rm -it ghcr.io/underhax/authelia-docker:latest crypto hash generate pbkdf2 --variant sha512
   ```

3. **Configure OIDC Clients and Validate:**
   Add client definitions under `identity_providers.oidc` in `/home/authelia/config/configuration.yml`:
   ```bash
   sudo nano /home/authelia/config/configuration.yml
   ```
   Validate the updated configuration syntax and secret resolution prior to restarting the container:
   ```bash
   sudo docker run --rm \
     -e X_AUTHELIA_CONFIG_FILTERS=template \
     -v /home/authelia/config:/config:ro \
     -v /home/authelia/secrets:/run/secrets:ro \
     ghcr.io/underhax/authelia-docker:latest \
     config validate --config /config/configuration.yml
   ```

### 8. Configure Host Log Rotation (Optional)

Configure log rotation on the host to rotate container logs daily and signal Authelia to reopen log descriptors via SIGHUP:

1. **Deploy `/etc/logrotate.d/authelia`:**
   ```bash
   REPO="https://raw.githubusercontent.com/underhax/authelia-docker/main"

   sudo curl -fsSL ${REPO}/etc/logrotate.d/authelia -o /etc/logrotate.d/authelia
   sudo chown root:root /etc/logrotate.d/authelia
   sudo chmod 0400 /etc/logrotate.d/authelia
   ```

2. **Verify Configuration:**
   Validate logrotate syntax in debug mode:
   ```bash
   sudo logrotate -d /etc/logrotate.d/authelia
   ```

### 9. Start the Stack

Pull the latest release and start the service in detached mode:

```bash
sudo docker compose -f /home/authelia/docker-compose.yaml pull
sudo docker compose -f /home/authelia/docker-compose.yaml up -d
```

</details>

---

<details>
<summary><strong>Operation &amp; Maintenance</strong></summary>

### Verifying Service Health

Check container status and resource consumption:

```bash
sudo docker compose -f /home/authelia/docker-compose.yaml ps
sudo docker stats --no-stream authelia
```

### Inspecting Runtime Logs

Follow service logs in real time:

```bash
sudo docker compose -f /home/authelia/docker-compose.yaml logs -f
```

### Tearing Down the Stack

Stop and remove the container:

```bash
sudo docker compose -f /home/authelia/docker-compose.yaml down
```

</details>

---

<details>
<summary><strong>Development</strong></summary>

For local compilation, testing, static analysis, and CI/CD details, see **[DEVELOPMENT.md](DEVELOPMENT.md)**.

</details>

---

<details>
<summary><strong>License &amp; Attribution</strong></summary>

## License & Attribution

This repository and deployment architecture are licensed under the [MIT License](LICENSE).

**Authelia License & Ownership:** Authelia is open-source software licensed under the [Apache License 2.0](https://github.com/authelia/authelia/blob/master/LICENSE) and developed by the [Authelia Team](https://github.com/authelia).

</details>
