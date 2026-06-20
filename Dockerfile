# 1. Tentukan base image (fondasi OS + Web Server yang mau dipakai)
FROM nginx:alpine

# 2. Salin file web statis dari laptop ke dalam folder default Nginx di container
COPY index.html /usr/share/nginx/html/

# 3. Informasikan port yang dibuka oleh container ini secara internal
EXPOSE 80