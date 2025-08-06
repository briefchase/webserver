#!/bin/bash
# Blank Apache setup for Debian/Ubuntu images (tested on Debian 11).
# Installs Apache, PHP, and Certbot. Creates a simple index.html with "hey".
# Usage: sudo bash start.sh

set -euo pipefail

CONFIG_FILE="/tmp/config.json"
DEPLOY_CONFIG_FILE="/tmp/apache_deploy/deploy_config.json"

log() { echo -e "[${DEPLOYMENT_NAME:-apache-provision}] $*"; }

ensure_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  apt-get update -y && apt-get install -y jq
}

init_config() {
  ensure_jq
  
  # Try to read deployment name from deploy config first
  if [[ -f "$DEPLOY_CONFIG_FILE" ]]; then
    DEPLOYMENT_NAME=$(jq -r '.deployment_name // "apache-server"' "$DEPLOY_CONFIG_FILE")
    log "Using deployment name from config: $DEPLOYMENT_NAME"
  else
    DEPLOYMENT_NAME="apache-server"
    log "No deployment config found, using default name: $DEPLOYMENT_NAME"
  fi
  
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log "Creating initial $CONFIG_FILE …"
    cat > "$CONFIG_FILE" <<JSON
{
  "deployment_name": "$DEPLOYMENT_NAME",
  "sites": [],
  "admin_email": "admin@example.com"
}
JSON
  fi

  ADMIN_EMAIL=$(jq -r '.admin_email // "admin@example.com"' "$CONFIG_FILE")
}

update_system() {
  log "Updating system packages …"
  
  # Set non-interactive frontend early
  export DEBIAN_FRONTEND=noninteractive
  export APT_LISTCHANGES_FRONTEND=none
  export NEEDRESTART_MODE=a
  
  log "Disabling installation of documentation to speed up apt."
  echo 'path-exclude /usr/share/doc/*' | tee /etc/dpkg/dpkg.cfg.d/01_nodoc
  echo 'path-exclude /usr/share/man/*' | tee -a /etc/dpkg/dpkg.cfg.d/01_nodoc
  echo 'path-exclude /usr/share/info/*' | tee -a /etc/dpkg/dpkg.cfg.d/01_nodoc
  echo 'path-exclude /usr/share/locale/*' | tee -a /etc/dpkg/dpkg.cfg.d/01_nodoc
  
  # Disable man-db triggers to prevent hanging
  log "Disabling man-db triggers to prevent hanging..."
  echo 'man-db man-db/auto-update boolean false' | debconf-set-selections
  
  log "Killing any existing apt processes to prevent locks..."
  pkill -9 -f apt || true
  rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock /var/lib/apt/lists/lock
  dpkg --configure -a --force-confdef
  
  # Update with timeout protection
  log "Running apt-get update with timeout protection..."
  timeout 300 apt-get update -y || {
    log "Warning: apt-get update timed out, continuing anyway..."
  }
}

install_stack() {
  log "Installing Apache, PHP, and Certbot …"
  export DEBIAN_FRONTEND=noninteractive
  export APT_LISTCHANGES_FRONTEND=none
  export NEEDRESTART_MODE=a
  
  # Install packages with timeout protection
  log "Running package installation with timeout protection..."
  timeout 1800 apt-get -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    -o Dpkg::Options::="--force-confnew" \
    install apache2 php libapache2-mod-php certbot python3-certbot-apache wget jq || {
    log "Warning: Package installation timed out or failed, attempting recovery..."
    
    # Kill any hanging processes
    pkill -9 -f mandb || true
    pkill -9 -f "Building database" || true
    
    # Try to configure any partially installed packages
    dpkg --configure -a --force-confdef || true
    
    log "Continuing with service configuration..."
  }
  
  log "Enabling Apache service..."
  systemctl enable apache2
  
  log "Starting Apache service..."
  if ! systemctl start apache2; then
    log "ERROR: 'systemctl start apache2' command failed."
    systemctl status apache2 --no-pager || true
    journalctl -u apache2 -n 50 --no-pager || true
    return 1
  fi
  
  # Wait for Apache to become active
  for i in {1..10}; do
    if systemctl is-active --quiet apache2; then
      log "Apache started successfully (attempt $i)."
      break
    fi
    if [ $i -eq 10 ]; then
      log "ERROR: Apache failed to become active after 10 attempts."
      systemctl status apache2 --no-pager || true
      return 1
    fi
    log "Apache not active yet, waiting... (attempt $i/10)"
    sleep 1
  done
  
  log "Enabling Apache rewrite module..."
  a2enmod rewrite

  log "Configuring Apache to allow .htaccess overrides..."
  local apache_config="/etc/apache2/apache2.conf"
  if ! grep -q "AllowOverride All" "$apache_config"; then
      sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' "$apache_config"
      log "Enabled .htaccess overrides in $apache_config"
  else
      log ".htaccess overrides already seem to be enabled."
  fi

  systemctl restart apache2
  log "Apache configuration restarted"
}

create_index_page() {
  local deploy_dir="/tmp/apache_deploy"
  local public_dir="$deploy_dir/public"
  
  log "Setting up web content..."
  
  # Remove default Apache page
  rm -f /var/www/html/index.html
  
  # Check if we have deployed files in the public directory
  if [ -d "$public_dir" ] && [ "$(ls -A "$public_dir" 2>/dev/null)" ]; then
    log "Found deployed files in 'public' directory, copying to web root..."
    
    # Copy all contents from public_dir to the web root
    cp -r "$public_dir"/* /var/www/html/ || {
      log "Error: Failed to copy files from $public_dir"
      create_fallback_page
      return 1
    }
    
    log "Deployed files copied successfully."
  else
    log "No deployed content found in '$public_dir', creating fallback page."
    create_fallback_page
  fi
  
  # Set proper permissions
  chown -R www-data:www-data /var/www/html/
  chmod -R 755 /var/www/html/
  
  log "Web content setup complete"
}

configure_ssl() {
  local deploy_dir="/tmp/apache_deploy"
  local config_file="$deploy_dir/deploy_config.json"
  
  # Check if we have a domain configuration
  if [ -f "$config_file" ]; then
    local domain=$(jq -r '.domain // empty' "$config_file" 2>/dev/null || echo "")
    local ssl_email=$(jq -r '.ssl_email // empty' "$config_file" 2>/dev/null || echo "")
    
    if [ -n "$domain" ] && [ -n "$ssl_email" ] && [[ ! "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      log "Configuring SSL certificate for domain: $domain"
      
      # Run certbot to get SSL certificate
      certbot --apache -d "$domain" --email "$ssl_email" --agree-tos --non-interactive --redirect || {
        log "Warning: SSL certificate configuration failed. Site will run on HTTP."
        return 1
      }
      
      log "SSL certificate configured successfully for $domain"
      return 0
    fi
  fi
  
  log "No domain configuration found or IP address detected. Skipping SSL setup."
  return 0
}

create_fallback_page() {
  log "Creating fallback page for $DEPLOYMENT_NAME..."
  
  # Create simple fallback page
  cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$DEPLOYMENT_NAME - Apache Server</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background-color: #f0f0f0;
        }
        .container {
            text-align: center;
            background: white;
            padding: 2rem;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            margin: 0;
        }
        .info {
            color: #666;
            margin-top: 1rem;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>$DEPLOYMENT_NAME</h1>
        <div class="info">
            <p>Apache server is running!</p>
            <p>Apache + PHP + Certbot</p>
        </div>
    </div>
</body>
</html>
HTML
}

main() {
  init_config
  update_system
  install_stack
  create_index_page
  configure_ssl

  log "Apache server provisioning complete!"
  
  # Fetch external IP from metadata and log it
  EXT_IP=$(curl -s -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" || true)
  if [[ -n "$EXT_IP" ]]; then
    log "Address: http://$EXT_IP"
  fi
}

main "$@" 