#!/bin/bash

# Helper function to get GCP Project ID
get_project_id() {
    gcloud config get-value project 2>/dev/null
}

# Function to check and install Terraform
check_terraform() {
    if command -v terraform &>/dev/null; then
        echo "Terraform installation was verified."
        return 0
    fi
    echo "Terraform is not installed. Attempting installation."
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null || { echo "Error: Failed to add HashiCorp GPG key." >&2; return 1; }
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null || { echo "Error: Failed to add HashiCorp repository." >&2; return 1; }
    sudo apt update && sudo apt install -y terraform || { echo "Error: Failed to install Terraform." >&2; return 1; }
    echo "Terraform was installed successfully."
}

# Function to check and setup GCP SDK and environment (simplified for Apache deployment)
check_gcp() {
    if ! command -v gcloud &>/dev/null; then
        echo "Google Cloud SDK is not installed. Attempting installation."
        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null || { echo "Error: Adding the GCloud repository failed." >&2; return 1; }
        curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - || { echo "Error: Adding the GCloud key failed." >&2; return 1; }
        sudo apt update && sudo apt install -y google-cloud-sdk || { echo "Error: Installing the GCloud SDK failed." >&2; return 1; }
        echo "Google Cloud SDK was installed successfully."
    else
        echo "Google Cloud SDK installation was verified."
    fi

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        echo "Google Cloud authentication is required."
        gcloud auth login --no-launch-browser || { echo "Error: GCloud login failed." >&2; return 1; }
        echo "Google Cloud authentication succeeded."
    else
        echo "Google Cloud authentication was verified."
    fi

    local project_id=$(get_project_id)
    if [ -z "$project_id" ] || [ "$project_id" = "(unset)" ]; then
        echo "No GCP project is configured."
        read -p "Enter your GCP project ID: " new_project_id
        read -p "Enter your GCP project name: " project_name
        gcloud projects create "$new_project_id" --name="$project_name" || echo "Project creation might have failed (the project may already exist)." >&2
        gcloud config set project "$new_project_id" || { echo "Error: Setting the project failed." >&2; return 1; }
        project_id="$new_project_id"
        echo "The GCP project was set to: $project_id."
    else
        echo "The GCP project is configured: $project_id."
    fi

    local billing_status=$(gcloud billing projects describe "$project_id" --format="get(billingEnabled)" 2>/dev/null)
    if [ "$billing_status" != "True" ]; then
        echo "Error: No billing account was found for project $project_id, or billing is not enabled. Please set up billing:" >&2
        echo "1. Visit https://console.cloud.google.com/billing" >&2
        echo "2. Link project '$project_id' to a billing account." >&2
        echo "3. Run this script again." >&2
        return 1
    else
        echo "Billing was verified for project $project_id."
    fi

    # Enable necessary APIs for VM deployment
    gcloud services enable compute.googleapis.com cloudresourcemanager.googleapis.com iam.googleapis.com --project="$project_id" || { echo "Error: Enabling one or more required GCP services failed." >&2; return 1; }
    echo "Required Google Cloud services were enabled."
}

# Function to check and install Apache and related tools
check_apache() {
    if command -v apache2 &>/dev/null; then
        echo "Apache installation was verified."
        return 0
    fi
    echo "Apache is not installed. Attempting installation."
    
    # Update package list
    sudo apt-get update || { echo "Error: Failed to update package list." >&2; return 1; }
    
    # Install Apache, PHP, and related tools
    sudo apt-get install -y apache2 php libapache2-mod-php certbot python3-certbot-apache wget curl tar gzip || { echo "Error: Failed to install Apache and related packages." >&2; return 1; }
    
    # Enable Apache modules
    sudo a2enmod rewrite || { echo "Warning: Failed to enable rewrite module." >&2; }
    sudo a2enmod ssl || { echo "Warning: Failed to enable SSL module." >&2; }
    
    # Enable and start Apache service
    sudo systemctl enable apache2 || { echo "Warning: Failed to enable Apache service." >&2; }
    sudo systemctl start apache2 || { echo "Warning: Failed to start Apache service." >&2; }
    
    echo "Apache was installed and configured successfully."
}

# Function to check and install Node.js for JavaScript obfuscation
check_nodejs() {
    if command -v node &>/dev/null && command -v npm &>/dev/null; then
        echo "Node.js and npm installation was verified."
        return 0
    fi
    echo "Node.js/npm is not installed. Attempting installation."
    
    # Install Node.js and npm
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - || { echo "Error: Failed to add Node.js repository." >&2; return 1; }
    sudo apt-get install -y nodejs || { echo "Error: Failed to install Node.js." >&2; return 1; }
    
    echo "Node.js and npm were installed successfully."
}

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Attempting to install..."
    if command -v sudo &> /dev/null && command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v sudo &> /dev/null && command -v yum &> /dev/null; then
        sudo yum install -y jq
    elif command -v sudo &> /dev/null && command -v dnf &> /dev/null; then
        sudo dnf install -y jq
    else
        echo "Error: Could not install jq automatically. Please install it manually using your system's package manager." >&2
        return 1
    fi
    if ! command -v jq &> /dev/null; then
        echo "Error: jq installation failed. Please install it manually." >&2
        return 1
    fi
    echo "jq has been successfully installed."
fi

# Allow calling functions directly if script is executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script (${BASH_SOURCE[0]}) is intended to be sourced. Use the main 'go.sh' script instead." >&2
    exit 1
fi
