# <Nama Aplikasi> — Production Deployment

> UAS Sistem Operasi + Jaringan Komputer — Kelas Sentul, Sesi 16

Static HTML site yang dideploy ke VPS dengan domain HTTPS (via nginx + certbot), auto-deploy lewat GitHub Actions, monitoring via Uptime Kuma, dan backup harian otomatis menggunakan layanan fratis dari Backblaze.

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
6. **Cron job** backup data aplikasi tiap hari ke Cloud Storage eksternal menggunakan layanan gratis dari Backblaze.

### Tech Stack
| Layer | Tools |
|---|---|
| App | Static HTML (`<index.html>`) |
| Web server / reverse proxy | nginx |
| SSL | certbot (Let's Encrypt) |
| Container | Docker + Docker Compose |
| CI/CD | GitHub Actions |
| Monitoring | Uptime Kuma |
| Backup | cron job → `<B2, Backblaze>` |
| VPS Provider | `<Herza>` |
| Domain | `<hi-hima.my.id>` |

## 2. Struktur Repo

```
.
UAS-WEB-DEPLOYMENT/
├── .github/
│   └── workflows/
│       └── deploy.yml        # CI/CD pipeline — trigger saat push ke main
├── html/
│   └── index.html            # aplikasi static yang di-serve nginx
├── docker-compose.yml        # definisi App Container (nginx + static html)
└── README.md
```

---

## 3. Setup & Deployment

### 3.1 Domain & DNS
- Main Domain                       : `<hi-hima.my.id>`
- Sub Domain                        : `<www.hi-hima.my.id>`
- Monitoring Domain                 : `<monitor.hi-hima.my.id>`
- DNS A record mengarah ke IP VPS   : `<103.168.146.195>`

### 3.2 VPS
- Provider: `<Herza>`
- OS: `<Ubuntu 24.04>`
- Spesifikasi: `<RAM 1GB/1CPU/disk>`

### 3.3 nginx + HTTPS (certbot)

```nginx
server {
    server_name hi-hima.my.id www.hi-hima.my.id;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/hi-hima.my.id/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/hi-hima.my.id/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
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

### 3.4 CI/CD (GitHub Actions)
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

### 3.5 Container (Docker Compose)
```yaml
version: '3.8'

services:
  web-uas:
    image: nginx:latest
    container_name: web_uas_zazhran
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html
    restart: always

  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: monitoring_uas_zazhran
    ports:
      - "3001:3001" 
    volumes:
      - uptime-kuma-data:/app/data
    restart: always

volumes:
  uptime-kuma-data:
```

### 3.6 Monitoring
- Dashboard Uptime Kuma: `http://monitor.hi-hima.my.id`
- Interval check: 60 detik

### 3.7 Logging
- Log aplikasi (nginx access/error): `docker logs <nama_container_app>`
- Atau via journalctl jika service dijalankan langsung: `journalctl -u <nama_service> -f`

### 3.8 Backup
Cron job harian (`crontab -e` di VPS):
```bash
0 2 * * * /home/<user>/scripts/backup.sh >> /var/log/backup.log 2>&1
```

Isi `backup.sh` (contoh, sesuaikan dengan provider storage):
```bash
#!/bin/bash
BACKUP_DIR="/home/zazhran/tugas-uas/html"
DEST_ZIP="/home/zazhran/backup_uas_$(date +%Y%m%d_%H%M%S).zip"
BUCKET_NAME="backup-uas-zazhran"

echo "Memulai backup folder HTML..."
zip -r $DEST_ZIP $BACKUP_DIR

echo "Mengirim file ke Cloud Storage Backblaze..."
rclone copy $DEST_ZIP mybackup:$BUCKET_NAME --s3-no-check-bucket

rm $DEST_ZIP
```

---


## 4. Lessons Learned

- `<Simulasi Web deployment>`
Meskipun ini diperuntukan untuk tugas, namun pengalaman yang didapatkan sudah bisa di aplikasikan bahkan bisa mulai menarik client
- `<Jasa sewa lahan di VPS>`
Saya membuka jasa sewa lahan VPS untuk teman teman saya dan ternyata memberi saya pengalaman seperti memanage access antar user seperti ketika meminta akses NGINX dan Certificate HTTPS hanya bisa dilakukan oleh pemilik tahta tertinggi yaitu root atau saya sendiri menggunakan sudo.
---

## 5. Referensi
- https://software.endy.muhardin.com/devops/deployment-microservice-kere-hore-1/
