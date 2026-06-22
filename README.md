# <Nama Aplikasi> — Production Deployment

> UAS Sistem Operasi + Jaringan Komputer — Kelas Sentul, Sesi 16
> Kelompok: `<nama anggota 1, 2, 3>`

Static HTML site yang dideploy ke VPS dengan domain HTTPS (via nginx + certbot), auto-deploy lewat GitHub Actions, monitoring via Uptime Kuma, dan backup harian otomatis.

---

## 1. Architecture Diagram

```
Developer laptop
      │ git push (main)
      ▼
GitHub Repo ──trigger──► GitHub Actions (CI/CD)
                                │
                                │ SSH deploy
                                ▼
                         ┌─────────────── VPS Server ───────────────┐
                         │                                          │
   User Browser          │   nginx :80,:443  ──proxy_pass──►  App   │
   ──resolve domain──►   │   (SSL via certbot)                Container│
   (Domain DNS A record) │        ▲                          (Docker)│
                         │        │ health check                    │
                         │   Uptime Kuma (sibling container)         │
                         │                                          │
                         │   cron job ──daily backup──►  Cloud      │
                         │                                Storage    │
                         │                              (S3/R2/B2)   │
                         └──────────────────────────────────────────┘
```

**Alur:**
1. Developer `git push` ke branch `main` di GitHub Repo.
2. GitHub Actions otomatis jalan: build (jika perlu) → SSH ke VPS → `docker compose pull && up -d`.
3. User akses domain → DNS resolve ke IP VPS → request HTTPS ke nginx → nginx `proxy_pass` ke App Container.
4. nginx jadi reverse proxy; SSL cert dikelola **certbot** (Let's Encrypt), auto-renew via systemd timer / cron.
5. **Uptime Kuma** polling endpoint tiap menit untuk cek uptime.
6. **Cron job** backup data aplikasi tiap hari ke Cloud Storage eksternal.

### Tech Stack
| Layer | Tools |
|---|---|
| App | Static HTML (`<nama file, mis. index.html>`) |
| Web server / reverse proxy | nginx |
| SSL | certbot (Let's Encrypt) |
| Container | Docker + Docker Compose |
| CI/CD | GitHub Actions |
| Monitoring | Uptime Kuma |
| Backup | cron job → `<S3 / R2 / B2, sebutkan provider>` |
| VPS Provider | `<nama provider, mis. DigitalOcean / Vultr / Contabo>` |
| Domain | `<nama domain>` |

---

## 2. Pembagian Peran Kelompok

| Nama | Peran / Tanggung jawab |
|---|---|
| `<anggota 1>` | `<mis. VPS setup, nginx, certbot>` |
| `<anggota 2>` | `<mis. CI/CD pipeline, GitHub Actions>` |
| `<anggota 3>` | `<mis. monitoring, backup, dokumentasi>` |

---

## 3. Struktur Repo

```
.
├── index.html              # aplikasi static
├── docker-compose.yml       # definisi App Container (+ Uptime Kuma jika di-bundle)
├── nginx/
│   └── <domain>.conf        # config reverse proxy
├── .github/
│   └── workflows/
│       └── deploy.yml       # CI/CD pipeline
├── scripts/
│   └── backup.sh            # script backup ke cloud storage
└── README.md
```

---

## 4. Setup & Deployment

### 4.1 Domain & DNS
- Domain: `<nama domain>`
- DNS A record mengarah ke IP VPS: `<IP VPS>`
- Registrar: `<nama registrar>`

### 4.2 VPS
- Provider: `<nama provider>`
- OS: `<mis. Ubuntu 22.04>`
- Spesifikasi: `<RAM/CPU/disk>`
- Akses SSH: `ssh <user>@<domain atau IP>`

### 4.3 nginx + HTTPS (certbot)
Config reverse proxy ada di `/etc/nginx/sites-available/<domain>`:

```nginx
server {
    listen 80;
    server_name <domain>;

    location / {
        proxy_pass http://localhost:<port_app>;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

SSL cert di-generate dengan:
```bash
sudo certbot --nginx -d <domain>
```

Auto-renew dicek via:
```bash
sudo systemctl status certbot.timer
# atau
sudo certbot renew --dry-run
```

### 4.4 CI/CD (GitHub Actions)
File: `.github/workflows/deploy.yml`

Trigger: setiap push ke `main` →
1. Checkout code
2. (Opsional) build/test jika ada
3. SSH ke VPS
4. `docker compose pull && docker compose up -d`

Secrets yang dibutuhkan di GitHub repo (`Settings → Secrets`):
- `VPS_HOST`
- `VPS_USER`
- `VPS_SSH_KEY`

### 4.5 Container (Docker Compose)
```yaml
services:
  app:
    image: nginx:alpine
    volumes:
      - ./:/usr/share/nginx/html:ro
    ports:
      - "<port_app>:80"
    restart: unless-stopped

  uptime-kuma:
    image: louislam/uptime-kuma:1
    ports:
      - "3001:3001"
    volumes:
      - uptime-kuma-data:/app/data
    restart: unless-stopped

volumes:
  uptime-kuma-data:
```

### 4.6 Monitoring
- Dashboard Uptime Kuma: `http://<IP_VPS>:3001` (atau subdomain jika di-proxy)
- Endpoint yang dimonitor: `https://<domain>`
- Interval check: 60 detik

### 4.7 Logging
- Log aplikasi (nginx access/error): `docker logs <nama_container_app>`
- Atau via journalctl jika service dijalankan langsung: `journalctl -u <nama_service> -f`

### 4.8 Backup
Cron job harian (`crontab -e` di VPS):
```bash
0 2 * * * /home/<user>/scripts/backup.sh >> /var/log/backup.log 2>&1
```

Isi `backup.sh` (contoh, sesuaikan dengan provider storage):
```bash
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
tar -czf /tmp/backup_$TIMESTAMP.tar.gz /path/to/app/data
aws s3 cp /tmp/backup_$TIMESTAMP.tar.gz s3://<bucket-name>/backups/
rm /tmp/backup_$TIMESTAMP.tar.gz
```

---

## 5. Runbook

### 5.1 Restart Procedure
```bash
ssh <user>@<domain>
cd /path/to/project
docker compose restart app
# verify
docker ps -a
curl -I https://<domain>
```

### 5.2 Rollback Procedure
```bash
# Lihat history commit
git log --oneline -5

# Revert commit terakhir di main
git revert HEAD
git push origin main
# GitHub Actions otomatis re-deploy versi sebelumnya
```

Jika perlu rollback manual di VPS (tanpa CI/CD):
```bash
ssh <user>@<domain>
cd /path/to/project
git pull
docker compose down
docker compose up -d --build
```

### 5.3 Restore from Backup
```bash
# Download backup terbaru dari cloud storage
aws s3 cp s3://<bucket-name>/backups/<file_backup_terbaru> /tmp/

# Extract
tar -xzf /tmp/<file_backup_terbaru> -C /path/to/restore

# Restart service terkait
docker compose restart app
```

### 5.4 Troubleshooting Cepat (checklist)
| Symptom | Cek |
|---|---|
| Site unreachable | `dig <domain>`, `curl -I https://<domain>`, `ufw status` |
| HTTPS error | `sudo certbot certificates`, `nginx -t`, `tail /var/log/nginx/error.log` |
| App down | `docker ps -a`, `docker logs <container>` |
| Disk penuh | `df -h`, cari junk file besar (`du -sh /var/log/* \| sort -h`) |
| Deploy gagal | Cek tab **Actions** di GitHub, baca log step yang gagal |

---

## 6. Operational Notes

- **Lokasi log nginx**: `/var/log/nginx/access.log`, `/var/log/nginx/error.log`
- **Lokasi log app**: `docker logs <nama_container>` atau `<path log app jika static file served langsung>`
- **Cara cek monitoring**: buka `http://<IP_VPS>:3001`, lihat status uptime endpoint `<domain>`
- **File `.env`** (jika ada): lokasi `/path/to/project/.env`, isi variable `<sebutkan, mis. API_KEY, DB_CONN>` — **jangan commit ke repo**, sudah masuk `.gitignore`
- **Cara cek sertifikat SSL**: `sudo certbot certificates`

---

## 7. Lessons Learned

- `<isi setelah sesi 9–15: apa yang sempat error, gimana cara fix-nya, apa yang dipelajari>`

---

## 8. Referensi
- Arsitektur sistem & alur deployment: dokumen UAS Sesi 16, STMIK TAZKIA
