#!/bin/bash

# Function to create secrets.json - REMOVED
# create_secrets() { ... }

# Function to prompt for secrets and send using curl
tell_secrets() {
    local template_dir="$(dirname "$0")/../templates"
    local template_file="$template_dir/secrets.template.json"
    local secret_keys
    local key
    local value
    local json_payload="{"
    local first_key=true

    [ ! -f "$template_file" ] && { echo "Error: The template '$template_file' was not found." >&2; return 1; }

    echo "Reading secret keys from template: $template_file"
    # Extract keys (lines containing ": "", then strip quotes and colon)
    secret_keys=$(grep '"\w*"\s*:' "$template_file" | sed 's/"//g; s/\s*://g; s/,//g')

    if [ -z "$secret_keys" ]; then
        echo "Error: Could not extract any secret keys from '$template_file'." >&2
        return 1
    fi

    echo "Please enter the values for the following secrets:"
    # Loop through each key
    while IFS= read -r key; do
        # Trim whitespace just in case
        key=$(echo "$key" | xargs)
        if [ -n "$key" ]; then
            # Prompt user for the value, -s hides input
            read -s -p "  Enter value for $key: " value
            echo "" # Add a newline after hidden input

            # Basic check if value is empty (optional, depends if empty secrets are allowed)
            # if [ -z "$value" ]; then
            #     echo "Warning: Value for $key is empty." >&2
            # fi

            # Append to JSON payload string, handling commas
            if [ "$first_key" = true ]; then
                first_key=false
            else
                json_payload+=,
            fi
            # Escape double quotes within the value for valid JSON
            local escaped_value=$(echo "$value" | sed 's/"/\\"/g')
            json_payload+="\"$key\":\"$escaped_value\""
        fi
    done <<< "$secret_keys"

    json_payload+="}"
    echo "JSON payload constructed."
    # echo "Debug Payload: $json_payload" # Uncomment for debugging

    # Prompt for URL
    local external_url=""
    read -p "Enter the URL to send secrets to (e.g., yourdomain.com or localhost:8000): " external_url
    [ -z "$external_url" ] && { echo "Error: The URL cannot be empty." >&2; return 1; }

    # Determine protocol
    local protocol="https"
    # ... (same protocol logic as before) ...
    if [[ "$external_url" == *"localhost"* ]] || [[ "$external_url" == "127.0.0.1"* ]] || [[ "$external_url" == *".local"* ]]; then
        if [[ "$external_url" != http://* ]] && [[ "$external_url" != https://* ]]; then
             protocol="http"
             external_url="http://$external_url"
             echo "HTTP protocol was assumed for the local URL: $external_url"
        elif [[ "$external_url" == https://* ]]; then
             read -p "The URL appears local but uses https. Use http instead? (y/n): " use_http
             if [[ "$use_http" =~ ^[Yy]$ ]]; then
                 protocol="http"
                 external_url="${external_url/https:/http:}"
                 echo "The URL was adjusted to use HTTP: $external_url"
             else
                 protocol="https"
                 echo "HTTPS protocol will be used for the local URL as specified."
             fi
        else # Starts with http://
             protocol="http"
        fi
    elif [[ "$external_url" != http://* ]] && [[ "$external_url" != https://* ]]; then
         external_url="https://$external_url"
         echo "The prefix https:// was added to the URL: $external_url"
    fi

    local target_endpoint="$external_url/set-secrets" # Assuming endpoint

    echo "Sending secrets to $target_endpoint..."
    # Send the constructed JSON payload directly
    curl -f -s -S -X POST -H "Content-Type: application/json" -d "$json_payload" "$target_endpoint" || {
        local curl_status=$?
        echo "Error: Curl command failed to send secrets to '$target_endpoint' (status $curl_status)." >&2
        [ $curl_status -eq 7 ] && echo "Hint: Connection failed. Ensure the server is running at '$external_url'." >&2
        [ $curl_status -eq 22 ] && echo "Hint: Server returned an error (e.g., 404 Not Found, 500 Internal Server Error)." >&2
        return 1
    }
    echo "Secrets were sent successfully to '$target_endpoint'."
}

# Function to create a backup
backup() {
    local instance_name="container-vm"
    local instance_zone="us-central1-a"
    local backup_filename="backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    local remote_acme_path="/etc/traefik/acme.json" # Path in Traefik container
    local script_dir; script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    local terraform_dir="$script_dir/../terraform"
    local local_temp_acme; local_temp_acme=$(mktemp /tmp/acme.json.remote.XXXXXX) || { echo "Error: Creating a temporary file failed." >&2; return 1; }
    # Ensure cleanup on exit/interrupt
    trap 'echo "Cleaning up temporary file: $local_temp_acme"; rm -f "$local_temp_acme"' EXIT INT TERM HUP

    # Try getting instance details from Terraform
    if command -v terraform &>/dev/null && [ -f "$terraform_dir/terraform.tfstate" ]; then
        local instance_name_tf=""
        local instance_zone_tf=""
        ( # Subshell for terraform output, ignore errors here
          cd "$terraform_dir" || { echo "Error: Could not cd to Terraform directory from $script_dir." >&2; return 1; }
          instance_name_tf=$(terraform output -raw instance_name 2>/dev/null || true)
          instance_zone_tf=$(terraform output -raw instance_zone 2>/dev/null || true)
        )
        [ -n "$instance_name_tf" ] && instance_name="$instance_name_tf" || echo "Warning: Could not get instance name from Terraform. Using default '$instance_name'." >&2
        [ -n "$instance_zone_tf" ] && instance_zone="$instance_zone_tf" || echo "Warning: Could not get instance zone from Terraform. Using default '$instance_zone'." >&2
        echo "Instance '$instance_name' in zone '$instance_zone' will be used for the backup."
    else
        echo "Warning: Terraform state not found or 'terraform' command unavailable. Using defaults: Name=$instance_name, Zone=$instance_zone." >&2
    fi

    # Find Traefik container ID via SSH (with sudo)
    local gcloud_ssh_cmd_find="sudo docker ps --filter ancestor=traefik:latest --format '{{.ID}}'"
    echo "Attempting to find Traefik container on '$instance_name'..."
    local container_id
    container_id=$(gcloud compute ssh "$instance_name" --zone "$instance_zone" --command="$gcloud_ssh_cmd_find" 2>/dev/null)
    local find_status=$?
    if [ $find_status -ne 0 ]; then
        echo "Error: Failed to execute SSH command to find Traefik container (Exit code: $find_status)." >&2
        echo "Hint: Ensure Docker daemon is running on the VM." >&2
        return 1
    fi
    if [ -z "$container_id" ]; then
         echo "Error: Could not find a running Traefik container on '$instance_name'. Is it deployed and running?" >&2
         return 1
    fi
    echo "The Traefik container ID '$container_id' was found."

    # Fetch acme.json from container via SSH (with sudo)
    local gcloud_ssh_cmd_cat="sudo docker exec $container_id cat $remote_acme_path"
    echo "Attempting to fetch '$remote_acme_path' from container '$container_id'..."
    gcloud compute ssh "$instance_name" --zone "$instance_zone" --command="$gcloud_ssh_cmd_cat" > "$local_temp_acme" 2>/dev/null
    local fetch_status=$?
    if [ $fetch_status -ne 0 ]; then
        echo "Error: Failed to execute SSH command to fetch acme.json (Exit code: $fetch_status)." >&2
        # Check if temp file is empty to differentiate network error vs file not found in container
        [ ! -s "$local_temp_acme" ] && echo "Hint: The temporary file is empty, the file might not exist at '$remote_acme_path' inside the container or the container is stopped." >&2
        return 1
    fi
    # Check if the fetched file has content
    if [ ! -s "$local_temp_acme" ]; then
         echo "Error: Fetched '$remote_acme_path', but the local temporary file '$local_temp_acme' is empty." >&2
         return 1
    fi
    echo "The file '$remote_acme_path' was fetched successfully to '$local_temp_acme'."

    # Create backup archive relative to the api/ directory
    local backup_dir="$script_dir/.." # api/
    tar czvf "$backup_dir/$backup_filename" -C "$(dirname "$local_temp_acme")" "$(basename "$local_temp_acme")" || {
        echo "Error: Failed to create the backup archive '$backup_dir/$backup_filename'." >&2
        # Keep trap active to clean up temp file on tar failure
        return 1
    }

    # Success: remove trap and temp file manually
    trap - EXIT INT TERM HUP # Disable trap
    rm -f "$local_temp_acme" || echo "Warning: Failed to clean up temporary file '$local_temp_acme'." >&2

    echo "The backup archive '$backup_dir/$backup_filename' was created successfully."
}

# Function to forcefully clean up Docker environment
docker_nuke() {
    echo "WARNING: This will forcefully stop and remove ALL Docker containers, networks, volumes," >&2
    echo "         and prune unused images. This is destructive and cannot be undone." >&2
    read -p "Are you absolutely sure you want to proceed? (y/n): " confirm_nuke
    if [[ ! "$confirm_nuke" =~ ^[Yy] ]]; then
        echo "Docker nuke operation cancelled." >&2
        return 1
    fi

    echo "Proceeding with Docker environment nuke..."

    # Stop all running containers
    echo "Stopping all running containers..."
    if sudo docker ps -q | grep .; then # Check if any containers are running
        sudo docker stop $(sudo docker ps -q) || echo "Warning: Some containers failed to stop." >&2
    else
        echo "No running containers found to stop."
    fi

    # Remove all containers (stopped and running)
    echo "Removing all containers..."
    if sudo docker ps -aq | grep .; then # Check if any containers exist
        sudo docker rm -f $(sudo docker ps -aq) || echo "Warning: Some containers failed to be removed." >&2
    else
        echo "No containers found to remove."
    fi

    # Remove all networks (except default ones)
    echo "Removing all Docker networks (except defaults)..."
    if sudo docker network ls -q | grep .; then # Check if any non-default networks exist
        sudo docker network prune -f || echo "Warning: Failed to prune networks." >&2
    else
        echo "No non-default networks found to prune."
    fi

    # Remove all volumes
    echo "Removing all Docker volumes..."
    if sudo docker volume ls -q | grep .; then # Check if any volumes exist
        sudo docker volume prune -f || echo "Warning: Failed to prune volumes." >&2
    else
        echo "No volumes found to prune."
    fi

    # Prune unused images
    echo "Pruning unused Docker images..."
    sudo docker image prune -af || echo "Warning: Failed to prune images." >&2

    echo "Docker environment nuke operation completed."
    return 0
}

# Function to connect to remote VM via SSH
connect_remote() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local terraform_dir="${script_dir}/../terraform"
    
    # Get instance name and zone from Terraform outputs, with defaults
    local instance_name_tf="container-vm"
    local instance_zone_tf="us-central1-a"
    
    # Try to get instance details from Terraform if available
    if [ -f "${terraform_dir}/terraform.tfstate" ]; then
        echo "Getting instance details from Terraform state..."
        instance_name_tf=$(terraform -chdir="${terraform_dir}" output -raw instance_name 2>/dev/null || echo "container-vm")
        instance_zone_tf=$(terraform -chdir="${terraform_dir}" output -raw instance_zone 2>/dev/null || echo "us-central1-a")
    else
        echo "Warning: Could not get instance details from Terraform. Using defaults."
    fi
    
    echo "Connecting to instance '${instance_name_tf}' in zone '${instance_zone_tf}'..."
    echo "Establishing SSH connection..."
    
    # Connect to the instance
    if ! gcloud compute ssh "${instance_name_tf}" --zone="${instance_zone_tf}"; then
        local exit_code=$?
        # Check if it's a normal SSH exit (130 is SIGINT/Ctrl+C)
        if [ $exit_code -eq 130 ]; then
            echo "SSH connection closed normally."
            return 0
        fi
        echo "Error: Failed to establish SSH connection (Exit code: ${exit_code})."
        echo "Possible reasons:"
        echo "1. The VM is not running"
        echo "2. Your gcloud configuration is incorrect"
        echo "3. You don't have the necessary permissions"
        echo "4. The VM is still starting up (wait a few minutes and try again)"
        return 1
    fi
}

# Function to forcefully clean up Docker environment on remote server
remote_docker_nuke() {
    echo "WARNING: This will forcefully stop and remove ALL Docker containers, networks, volumes," >&2
    echo "         and prune unused images on the remote server. This is destructive and cannot be undone." >&2
    read -p "Are you absolutely sure you want to proceed? (y/n): " confirm_nuke
    if [[ ! "$confirm_nuke" =~ ^[Yy] ]]; then
        echo "Remote Docker nuke operation cancelled." >&2
        return 1
    fi

    # Get instance details from Terraform state
    local terraform_dir="$_GO_SCRIPT_DIR/terraform"
    local instance_name
    local instance_zone

    if [ -f "$terraform_dir/terraform.tfstate" ]; then
        instance_name=$(cd "$terraform_dir" && terraform output -raw instance_name) || instance_name=""
        instance_zone=$(cd "$terraform_dir" && terraform output -raw instance_zone) || instance_zone=""
        
        if [ -z "$instance_name" ] || [ -z "$instance_zone" ]; then
            echo "Error: Could not get instance name or zone from Terraform state" >&2
            return 1
        fi
    else
        echo "Error: Terraform state file not found" >&2
        return 1
    fi

    echo "Proceeding with remote Docker environment nuke on $instance_name..."

    # Create a script to run on the remote server
    local remote_script="
        echo 'Stopping all running containers...'
        if sudo docker ps -q | grep .; then
            sudo docker stop \$(sudo docker ps -q) || echo 'Warning: Some containers failed to stop.'
        else
            echo 'No running containers found to stop.'
        fi

        echo 'Removing all containers...'
        if sudo docker ps -aq | grep .; then
            sudo docker rm -f \$(sudo docker ps -aq) || echo 'Warning: Some containers failed to be removed.'
        else
            echo 'No containers found to remove.'
        fi

        echo 'Removing all Docker networks (except defaults)...'
        if sudo docker network ls -q | grep .; then
            sudo docker network prune -f || echo 'Warning: Failed to prune networks.'
        else
            echo 'No non-default networks found to prune.'
        fi

        echo 'Removing all Docker volumes...'
        if sudo docker volume ls -q | grep .; then
            sudo docker volume prune -f || echo 'Warning: Failed to prune volumes.'
        else
            echo 'No volumes found to prune.'
        fi

        echo 'Pruning unused Docker images...'
        sudo docker image prune -af || echo 'Warning: Failed to prune images.'

        echo 'Remote Docker environment nuke operation completed.'
    "

    # Execute the script on the remote server
    echo "Executing nuke commands on remote server..."
    gcloud compute ssh "$instance_name" --zone "$instance_zone" --command="$remote_script" || {
        echo "Error: Failed to execute nuke commands on remote server" >&2
        return 1
    }

    echo "Remote Docker environment nuke operation completed successfully."
    return 0
}

# Function to check DNS resolution for a domain
check_dns_resolution() {
    local domain="$1"
    if [ -z "$domain" ]; then
        echo "Error: Domain must be provided to check_dns_resolution." >&2
        return 1
    fi

    echo "Checking DNS resolution for domain: $domain"
    if nslookup "$domain" &>/dev/null; then
        echo "DNS resolution successful for domain: $domain"
        return 0
    else
        echo "DNS resolution failed for domain: $domain"
        return 1
    fi
}

# Function to forcefully clean up Apache environment
apache_nuke() {
    echo "WARNING: This will stop Apache and remove all web files from /var/www/html." >&2
    echo "         This is destructive and cannot be undone." >&2
    read -p "Are you absolutely sure you want to proceed? (y/n): " confirm_nuke
    if [[ ! "$confirm_nuke" =~ ^[Yy] ]]; then
        echo "Apache nuke operation cancelled." >&2
        return 1
    fi

    echo "Proceeding with Apache environment cleanup..."

    # Stop Apache service
    echo "Stopping Apache service..."
    if systemctl is-active --quiet apache2; then
        sudo systemctl stop apache2 || echo "Warning: Failed to stop Apache service." >&2
    else
        echo "Apache service was not running."
    fi

    # Remove web files
    echo "Removing web files from /var/www/html..."
    sudo rm -rf /var/www/html/* || echo "Warning: Failed to remove some web files." >&2

    # Remove any deployment artifacts
    echo "Removing deployment artifacts..."
    sudo rm -rf /tmp/apache_deploy* || echo "Warning: Failed to remove deployment artifacts." >&2

    # Optionally restart Apache with default page
    read -p "Restart Apache with default page? (y/n): " restart_apache
    if [[ "$restart_apache" =~ ^[Yy] ]]; then
        sudo systemctl start apache2 || echo "Warning: Failed to restart Apache." >&2
        echo "Apache restarted with default configuration."
    fi

    echo "Apache environment cleanup completed."
    return 0
}

# Function to backup Apache configuration and web files
backup_apache() {
    local backup_filename="apache_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    local script_dir; script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    local backup_dir="$script_dir/.."

    echo "Creating Apache backup..."

    # Create backup of web files and Apache config
    sudo tar czvf "$backup_dir/$backup_filename" \
        -C /var/www/html . \
        --exclude='*.log' \
        --exclude='tmp' || {
        echo "Error: Failed to create the backup archive '$backup_dir/$backup_filename'." >&2
        return 1
    }

    echo "The backup archive '$backup_dir/$backup_filename' was created successfully."
    return 0
}

# Allow calling functions directly if script is executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script (${BASH_SOURCE[0]}) is intended to be sourced. Use the main 'go.sh' script instead." >&2
    exit 1
fi

# Export functions to be available to the main script
# Ensure this list is comprehensive
export -f tell_secrets
export -f backup
export -f docker_nuke
export -f connect_remote
export -f check_dns_resolution
export -f remote_docker_nuke
export -f apache_nuke
export -f backup_apache
# ... any other utility functions ...
