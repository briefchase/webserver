# Deployment Steps:
1. Create neccesary firewall rules (for GCP, AWS, or Azure)
2. Clone this repository onto server
3. Update & Upgrade, then install docker & docker-compose
4. Run the following commands:
 - sudo chmod 600 traefik/acme.json
 - sudo docker-compose up -d

# Info:
This server makes use of:
 - docker & docker-compose (deployment)
 - apache2 (serving public files)
 - traefik (load balancing, proxy, and ssl)

# Thanks!
Heres a cookie for coming this far 🍪. Feel free to make your own website using this as a template! Write your own website though, & dont serve my code.