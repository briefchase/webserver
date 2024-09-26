# Deployment Steps:
1. Create neccesary firewall rules (for GCP, AWS, or Azure)
2. Clone this repository onto server
3. Update, Upgrade and install make
 - ```sudo apt update && upgrade```
 - ```apt install make```
4. Usage:
 - ```make go``` - mounted
 - ```make live``` - headless
 - ```make clean``` - nuke cattle
5. Delete this repository (for production)

# Info:
This server makes use of:
 - docker & docker-compose (deployment)
 - apache2 (serving public files)
 - traefik (load balancing, proxy, and ssl)

# Thanks!
Heres a cookie for coming this far 🍪. Feel free to make your own website using this as a template! Write your own website though, & dont serve my code.