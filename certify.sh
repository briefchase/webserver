#!/bin/sh

sudo add-apt-repository ppa:certbot/certbot

sudo apt-get update

sudo apt-get install certbot

# Certbot needs to answer a cryptographic challenge issued by the Let’s Encrypt API in order to prove we control our domain. It uses ports 80 (HTTP) or 443 (HTTPS) to accomplish this.
sudo ufw allow 80

# Run Certbot to obtain the certificate
sudo certbot certonly --standalone --preferred-challenges dns \
  $DOMAINS \
  --cert-path ./cert/cert.pem \
  --key-path ./cert/privkey.pem \
  --fullchain-path ./cert/fullchain.pem