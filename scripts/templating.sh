#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Function to configure terraform.tfvars
# Accepts: overwrite_confirm_result ("y" or "n")
configure_tfvars() {
    local overwrite_confirm_result="$1"
    local project_id=$(get_project_id) # Relies on get_project_id defined in the sourcing script (go.sh)
    local template_file="$SCRIPT_DIR/../templates/terraform.template.tfvars"
    local tfvars_file="$SCRIPT_DIR/../terraform/terraform.tfvars"
    local create_tfvars=false

    [ ! -f "$template_file" ] && { echo "Error: Template '$template_file' not found." >&2; return 1; }

    # Check if terraform.tfvars exists
    if [ ! -f "$tfvars_file" ]; then
        echo "The file '$(basename "$tfvars_file")' does not exist. It will be created."
        create_tfvars=true
    else
        local existing_project_id=$(grep -E '^\\s*project_id\\s*=' "$tfvars_file" | sed -E 's/^\\s*project_id\\s*=\\s*"(.*)"\\s*$/\\1/')
        if [ "$existing_project_id" != "$project_id" ]; then
            # Use the passed-in confirmation result
            if [[ "$overwrite_confirm_result" =~ ^[Yy] ]]; then
                 echo "Project ID mismatch detected and overwrite confirmed."
                 create_tfvars=true
            else
                 echo "Project ID mismatch detected, but overwrite was declined. Update of '$(basename "$tfvars_file")' skipped."
            fi
        else
            echo "The project ID in '$(basename "$tfvars_file")' matches the current configuration. No update needed based on project ID."
        fi
    fi

    if [ "$create_tfvars" = true ]; then
        cp "$template_file" "$tfvars_file" || { echo "Error: Copying the template '$(basename "$template_file")' failed." >&2; return 1; }
        sed -i "s/your-project-id/$project_id/g" "$tfvars_file" || { echo "Error: Setting the project ID in '$(basename "$tfvars_file")' failed." >&2; return 1; }
        echo "The file '$(basename "$tfvars_file")' was created/updated with project ID: $project_id."
    fi
    return 0 # Explicitly return success
}



# Function to configure app/traefik/traefik.toml
# Accepts: deployment_type, ssl_email_result
configure_traefik() {
    local deployment_type="$1"
    local ssl_email_result="$2" # <-- Accept SSL email as parameter
    local template_file="$SCRIPT_DIR/../templates/traefik.template.toml"
    local target_dir="$SCRIPT_DIR/../app/traefik"
    local target_file="$target_dir/traefik.toml"
    local acme_file="$target_dir/acme.json"
    local dynamic_dir="$target_dir/dynamic"
    local force_https_template="$SCRIPT_DIR/../templates/force-https.template.toml"
    local force_https_file="$dynamic_dir/force-https.toml"

    [ -z "$deployment_type" ] && { echo "Error: Deployment type is required for configure_traefik." >&2; return 1; }
    [ ! -f "$template_file" ] && { echo "Error: Base template '$(basename "$template_file")' not found." >&2; return 1; }

    # Always start fresh from the base template
    mkdir -p "$target_dir" || { echo "Error: Failed to create directory '$target_dir'." >&2; return 1; }
    cp "$template_file" "$target_file" || { echo "Error: Failed copying '$(basename "$template_file")' to '$(basename "$target_file")'." >&2; return 1; }
    echo "Base Traefik configuration applied from '$(basename "$template_file")' to '$(basename "$target_file")'."

    # Conditionally add ACME/Let's Encrypt resolver for remote deployments
    if [ "$deployment_type" == "remote" ]; then
        echo "Configuring Traefik for remote deployment (adding Let's Encrypt resolver)..."

        # Check if the provided email is valid (basic check)
        if [ -z "$ssl_email_result" ]; then
            echo "Error: SSL email address was not provided for remote Traefik configuration." >&2
            return 1
        elif ! [[ "$ssl_email_result" =~ .+@.+ ]]; then
             echo "Warning: '$ssl_email_result' provided for SSL notifications does not look like a valid email address. Proceeding anyway." >&2
        fi

        # Ensure acme.json exists and has correct permissions
        if [ ! -f "$acme_file" ]; then
            touch "$acme_file" || { echo "Error: Failed to create '$(basename "$acme_file")'." >&2; return 1; }
            echo "Created empty '$(basename "$acme_file")'."
        fi
        chmod 600 "$acme_file" || { echo "Error: Failed to set permissions on '$(basename "$acme_file")'." >&2; return 1; }
        echo "Set permissions for '$(basename "$acme_file")' to 600."

        # Create dynamic directory and force-https configuration
        mkdir -p "$dynamic_dir" || { echo "Error: Failed to create dynamic directory." >&2; return 1; }
        if [ -f "$force_https_template" ]; then
            cp "$force_https_template" "$force_https_file" || { echo "Error: Failed to copy force-https template." >&2; return 1; }
            echo "Created force-https configuration in dynamic directory."
        else
            echo "Warning: force-https template not found at '$force_https_template'." >&2
        fi

        # Append the resolver configuration to traefik.toml using the provided email
        local escaped_ssl_email; escaped_ssl_email=$(echo "$ssl_email_result" | sed 's/\"/\\\"/g')
        {
            echo "" # Ensure newline before appending
            echo "[certificatesResolvers.lets-encrypt.acme]"
            echo "  storage = \"/etc/traefik/acme.json\"" # Path inside container
            echo "  email = \"$escaped_ssl_email\"" # Use the provided email
            echo "  [certificatesResolvers.lets-encrypt.acme.tlsChallenge]"
        } >> "$target_file" || { echo "Error: Failed appending Let's Encrypt config to '$(basename "$target_file")'." >&2; return 1; }

        # Verification step
        if grep -qF '[certificatesResolvers.lets-encrypt.acme]' "$target_file"; then
            echo "Let's Encrypt resolver configuration was appended to '$(basename "$target_file")'."
            local verify_email_cmd="grep -qE '^[[:space:]]*email[[:space:]]*=[[:space:]]*\"${escaped_ssl_email}\"' \"$target_file\""
            if eval "$verify_email_cmd"; then
                echo "Email '$ssl_email_result' was configured."
            else
                echo "Warning: Failed to verify email configuration in '$(basename "$target_file")' after appending." >&2
            fi
        else
            echo "Error: Failed to verify appending Let's Encrypt resolver block to '$(basename "$target_file")'. Check append logic." >&2
            return 1
        fi
    else
        echo "Skipping Traefik Let's Encrypt configuration for local deployment."
        # Ensure acme.json does not exist or is empty for local to avoid permission errors if mounted
        if [ -f "$acme_file" ]; then
            > "$acme_file" && echo "Emptied '$(basename "$acme_file")' for local setup."
        fi
        # Remove force-https configuration for local deployment
        if [ -f "$force_https_file" ]; then
            rm -f "$force_https_file" && echo "Removed force-https configuration for local setup."
        fi
    fi
    return 0 # Explicitly return success
}

# Function to configure .env file
# Accepts: deployment_type, flask_debug_result ("y" or "n"), external_url_result, cfg_http_port, cfg_https_port, cfg_local_image_name
configure_dotenv() {
    local deployment_type="$1"
    local flask_debug_result="$2"     # No default, passed from go.sh
    local external_url_result="$3"    # No default, passed from go.sh
    local cfg_http_port="$4"          # No default, passed from go.sh
    local cfg_https_port="$5"         # No default, passed from go.sh
    local cfg_local_image_name="$6"   # No default, passed from go.sh
    local app_dir="$SCRIPT_DIR/../app"
    local target_env_file="$app_dir/.env"
    local image_name=""
    local flask_debug="0" # Default to disabled

    [ -z "$deployment_type" ] && { echo "Error: The deployment type argument is missing." >&2; return 1; }
    [ -z "$external_url_result" ] && { echo "Error: The external URL result argument is missing." >&2; return 1; }
    [ ! -d "$app_dir" ] && { echo "Error: The directory '$app_dir' was not found." >&2; return 1; }

    # Base variables
    { # Group commands to write/overwrite the file
      echo "EXTERNAL_URL=$external_url_result"
      echo "CFG_HTTP_PORT=$cfg_http_port"
    } > "$target_env_file" || { echo "Error: Failed to create/update $(basename "$target_env_file")." >&2; return 1; }

    # Add FLASK_SECRET_KEY (should be available from environment due to export in go.sh for local)
    # For remote, it will be set directly in the execution environment of start.sh on the VM.
    if [ "$deployment_type" == "local" ]; then
        if [ -n "$FLASK_SECRET_KEY" ]; then
            echo "FLASK_SECRET_KEY=${FLASK_SECRET_KEY}" >> "$target_env_file" || { echo "Error: Failed appending FLASK_SECRET_KEY to $(basename "$target_env_file") for local." >&2; return 1; }
        else
            echo "Warning: FLASK_SECRET_KEY environment variable not set for local. It will not be added to .env file." >&2
        fi
    fi

    # Environment-specific variables
    case "$deployment_type" in
        local)
            image_name="$cfg_local_image_name"
            if [[ "$flask_debug_result" =~ ^[Yy] ]]; then
                flask_debug="1"
            fi
            # Append local-specific variables
            {
              echo "IMAGE_NAME=$image_name"
              echo "FLASK_DEBUG=$flask_debug"
              # Set this variable to enable the localhost route in docker-compose.dev.yml
              echo "ENABLE_LOCALHOST_ROUTE=-" # Any non-# value enables it
              # HTTPS Port is not used for local
            } >> "$target_env_file" || { echo "Error: Failed appending local vars to $(basename "$target_env_file")." >&2; return 1; }
            ;;
        remote)
            local project_id=$(get_project_id)
            [ -z "$project_id" ] || [ "$project_id" = "(unset)" ] && { echo "Error: GCP project ID is needed for remote deployment image name but is not set." >&2; return 1; }
            image_name="gcr.io/$project_id/server:latest"
            # Flask debug is forced off for remote
            flask_debug="0"
            # Append remote-specific variables
            {
              echo "IMAGE_NAME=$image_name"
              echo "FLASK_DEBUG=$flask_debug"
              echo "CFG_HTTPS_PORT=$cfg_https_port"
              # Set these variables to enable TLS in docker-compose.prod.yml
              echo "TRAEFIK_TLS_ENABLE="
              echo "TRAEFIK_TLS_RESOLVER="
              # ENABLE_LOCALHOST_ROUTE is not used for remote
            } >> "$target_env_file" || { echo "Error: Failed appending remote vars to $(basename "$target_env_file")." >&2; return 1; }
            ;;
        *)
            echo "Internal Error: Invalid deployment type '$deployment_type' was provided." >&2; return 1 ;;
    esac

    echo "The file '$(basename "$target_env_file")' was configured successfully for '$deployment_type' deployment."
    return 0 # Explicitly return success
}

# Function to run templating steps for Apache deployment
# Accepts: deployment_type, deployment_name, overwrite_confirm_result
template_files() {
    local deployment_type="$1"
    local deployment_name="$2"
    local overwrite_confirm_result="$3"

    [ -z "$deployment_type" ] && { echo "Error: Deployment type is required for template_files." >&2; return 1; }
    [ -z "$deployment_name" ] && { echo "Error: Deployment name is required for template_files." >&2; return 1; }

    echo "Running templating steps for '$deployment_type' Apache deployment..."

    # Configure Terraform variables only for remote deployments
    if [ "$deployment_type" == "remote" ]; then
        configure_tfvars "$overwrite_confirm_result" || { echo "Error: Failed to configure terraform.tfvars." >&2; return 1; }
    fi

    echo "Apache templating steps completed successfully."
}

# Allow calling functions directly if script is executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script (${BASH_SOURCE[0]}) is intended to be sourced. Use the main 'go.sh' script instead." >&2
    exit 1
fi 