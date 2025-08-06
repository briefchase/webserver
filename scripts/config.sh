#!/bin/bash

# Simple configuration for Apache deployment
export readonly REMOTE_APP_DIR="/var/www/html"

# Get project name from the directory of the main 'go.sh' script
# This makes the config file specific to the project (e.g., website, portfolio)
_PROJECT_NAME=${_GO_SCRIPT_DIR:+"$(basename "$_GO_SCRIPT_DIR")"}
readonly CONFIG_FILE="$HOME/.${_PROJECT_NAME:-default}_deploy_config"
readonly JSON_CONFIG_FILE="$_GO_SCRIPT_DIR/config.json"

# Helper function to get GCP Project ID
get_project_id() {
    gcloud config get-value project 2>/dev/null || echo "(unset)"
}

# Default configuration values
readonly DEFAULT_CONFIRM_APPLY="y"
readonly DEFAULT_LOCAL_HTTP_PORT="80"
readonly DEFAULT_REMOTE_HTTP_PORT="80"
readonly DEFAULT_REMOTE_HTTPS_PORT="443"
readonly DEFAULT_LOCAL_EXT_URL="localhost"

# Global configuration variables
CFG_SSL_EMAIL=""
CFG_EXTERNAL_URL=""
CFG_HTTP_PORT=""
CFG_HTTPS_PORT=""
CFG_CONFIRM_APPLY="n"
CFG_DEPLOYMENT_NAME=""

# Load saved configuration
load_config() {
    if [ -f "$JSON_CONFIG_FILE" ]; then
        CFG_SSL_EMAIL=$(jq -r '.ssl_email' "$JSON_CONFIG_FILE")
        CFG_EXTERNAL_URL=$(jq -r '.external_url' "$JSON_CONFIG_FILE")
        CFG_HTTP_PORT=$(jq -r '.http_port' "$JSON_CONFIG_FILE")
        CFG_HTTPS_PORT=$(jq -r '.https_port' "$JSON_CONFIG_FILE")
        CFG_CONFIRM_APPLY=$(jq -r '.confirm_apply' "$JSON_CONFIG_FILE")
        CFG_DEPLOYMENT_NAME=$(jq -r '.deployment_name' "$JSON_CONFIG_FILE")
    elif [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# Save configuration
save_config() {
    cat > "$CONFIG_FILE" <<EOF
# Apache deployment configuration
CFG_SSL_EMAIL="$CFG_SSL_EMAIL"
CFG_EXTERNAL_URL="$CFG_EXTERNAL_URL"
CFG_HTTP_PORT="$CFG_HTTP_PORT"
CFG_HTTPS_PORT="$CFG_HTTPS_PORT"
CFG_CONFIRM_APPLY="$CFG_CONFIRM_APPLY"
CFG_DEPLOYMENT_NAME="$CFG_DEPLOYMENT_NAME"
EOF
    echo "Configuration saved to $CONFIG_FILE"
}

# Simple configuration for local Apache deployment
configure_local_deployment() {
    CFG_EXTERNAL_URL="$DEFAULT_LOCAL_EXT_URL"
    CFG_HTTP_PORT="$DEFAULT_LOCAL_HTTP_PORT"
    echo "Local Apache deployment configured."
}

# Simple configuration for remote Apache deployment
configure_remote_deployment() {
    local main_script_dir="$1"
    
    # Load saved configuration
    load_config
    
    # First, ensure GCP configuration is set up
    echo "Setting up GCP configuration..."
    check_gcp || { echo "Error: GCP setup failed." >&2; return 1; }
    
    local project_id=$(get_project_id)
    echo "Using GCP project: $project_id"
    
    # Prompt for SSL email (use saved value as default)
    if [ -n "$CFG_SSL_EMAIL" ]; then
        read -p "Enter SSL email for Let's Encrypt [$CFG_SSL_EMAIL]: " ssl_email_input
        CFG_SSL_EMAIL="${ssl_email_input:-$CFG_SSL_EMAIL}"
    else
        read -p "Enter SSL email for Let's Encrypt: " CFG_SSL_EMAIL
        while [ -z "$CFG_SSL_EMAIL" ]; do
            echo "Error: SSL email cannot be empty for remote deployment."
            read -p "Enter SSL email: " CFG_SSL_EMAIL
        done
    fi
    
    # Prompt for external URL/domain (use saved value as default)
    if [ -n "$CFG_EXTERNAL_URL" ]; then
        local use_saved_input
        read -p "Use saved domain/URL ($CFG_EXTERNAL_URL)? (y/n) [default: y]: " use_saved_input
        local use_saved="${use_saved_input:-y}"
        
        if [[ ! "$use_saved" =~ ^[Yy]$ ]]; then
            CFG_EXTERNAL_URL=""
        fi
    fi
    
    if [ -z "$CFG_EXTERNAL_URL" ]; then
        local use_domain_input
        read -p "Use domain for URL? (y/n) [default: n]: " use_domain_input
        local use_domain="${use_domain_input:-n}"

        if [[ "$use_domain" =~ ^[Yy]$ ]]; then
            read -p "Enter domain: " CFG_EXTERNAL_URL
            while [ -z "$CFG_EXTERNAL_URL" ]; do
                echo "Error: Domain cannot be empty."
                read -p "Enter domain: " CFG_EXTERNAL_URL
            done
        else
            # Try to get IP from Terraform
            local tf_state_file="$main_script_dir/terraform/terraform.tfstate"
            local terraform_dir="$main_script_dir/terraform"
            local tf_ip=""
            
            if command -v terraform &>/dev/null && [ -f "$tf_state_file" ]; then
                tf_ip=$(cd "$terraform_dir" && terraform output -raw instance_public_ip 2>/dev/null) || tf_ip=""
            fi
            
            if [ -n "$tf_ip" ]; then
                local use_tf_ip_input
                read -p "Use detected Terraform IP ($tf_ip)? (y/n) [default: y]: " use_tf_ip_input
                local use_tf_ip="${use_tf_ip_input:-y}"
                
                if [[ "$use_tf_ip" =~ ^[Yy]$ ]]; then
                    CFG_EXTERNAL_URL="$tf_ip"
                fi
            fi
            
            if [ -z "$CFG_EXTERNAL_URL" ]; then
                read -p "Enter external IP or domain: " CFG_EXTERNAL_URL
                while [ -z "$CFG_EXTERNAL_URL" ]; do
                    echo "Error: External URL cannot be empty."
                    read -p "Enter external IP or domain: " CFG_EXTERNAL_URL
                done
            fi
        fi
    fi
    
    # Set ports
    CFG_HTTP_PORT="${CFG_HTTP_PORT:-$DEFAULT_REMOTE_HTTP_PORT}"
    CFG_HTTPS_PORT="${CFG_HTTPS_PORT:-$DEFAULT_REMOTE_HTTPS_PORT}"
    
    # Confirm Terraform apply
    local apply_input
    read -p "Apply Terraform plan? (y/n) [default: ${DEFAULT_CONFIRM_APPLY}]: " apply_input
    CFG_CONFIRM_APPLY="${apply_input:-$DEFAULT_CONFIRM_APPLY}"
    [[ "$CFG_CONFIRM_APPLY" =~ ^[Yy]$ ]] && CFG_CONFIRM_APPLY="y" || CFG_CONFIRM_APPLY="n"
    
    # Save configuration
    save_config
    
    echo "Remote Apache deployment configured."
}

# Main configuration function
# Args: $1 main_script_dir, $2 deployment_type
configure_deployment() {
    local main_script_dir="$1"
    local deployment_type="$2"
    
    case "$deployment_type" in
        "local")
            configure_local_deployment
            ;;
        "remote")
            configure_remote_deployment "$main_script_dir"
            ;;
        *)
            echo "Error: Invalid deployment type '$deployment_type'."
        return 1
            ;;
    esac
}

# Simple function to display current configuration
show_configuration() {
    echo "=== Apache Deployment Configuration ==="
    echo "Deployment Name: $CFG_DEPLOYMENT_NAME"
    echo "External URL: $CFG_EXTERNAL_URL"
    echo "HTTP Port: $CFG_HTTP_PORT"
    echo "HTTPS Port: $CFG_HTTPS_PORT"
    echo "SSL Email: $CFG_SSL_EMAIL"
    echo "Confirm Apply: $CFG_CONFIRM_APPLY"
    echo "================================="
}

# Allow calling functions directly if script is executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script (${BASH_SOURCE[0]}) is intended to be sourced. Use the main 'go.sh' script instead." >&2
    exit 1
fi
