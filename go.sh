#!/bin/bash

# Script Output Conventions:
# - Use complete sentences for all output messages.
# - Report actions only *after* they have been successfully completed or failed, using the past tense.
# Main Menu Modification:
# - Do not modify the main menu options without explicit user request.

#======================================
# Helper & Task Functions
#======================================
_GO_SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Source scripts in a way that makes functions available in current shell
source "$_GO_SCRIPT_DIR/scripts/config.sh" || { echo "Error: Failed to source config.sh" >&2; exit 1; }

# Check for jq and install if not present
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Attempting to install..."
    # Add installation command for your specific OS, e.g., sudo apt-get install jq
    sudo apt-get install -y jq || { echo "Error: Failed to install jq. Please install it manually." >&2; exit 1; }
fi

source "$_GO_SCRIPT_DIR/scripts/install.sh" || { echo "Error: Failed to source install.sh" >&2; exit 1; }
source "$_GO_SCRIPT_DIR/scripts/templating.sh" || { echo "Error: Failed to source templating.sh" >&2; exit 1; }
source "$_GO_SCRIPT_DIR/scripts/deploy.sh" || { echo "Error: Failed to source deploy.sh" >&2; exit 1; }
source "$_GO_SCRIPT_DIR/scripts/utilities.sh" || { echo "Error: Failed to source utilities.sh" >&2; exit 1; }

#======================================
# Main Menu & Script Execution
#======================================

show_menu() {
    echo "--- Apache Server Menu ---"
    echo " 1. Deploy Local Apache (localhost)"
    echo " 2. Deploy Remote Apache (GCP)"
    echo " 3. Nuke Menu"
    echo " 4. Exit"
    echo "-------------------------"
}

show_nuke_menu() {
    echo "--- Nuke Menu ---"
    echo "1. Nuke Local (Clean Apache)"
    echo "2. Nuke Remote (Destroy GCP Infrastructure)"
    echo "3. Back to Main Menu"
    echo "-------------------"
}

# Main script execution loop
while true; do
    show_menu
    read -p "Enter choice [1-4]: " choice
    echo ""

    # --- Configuration handled per deployment type ---

    operation_failed=false
    deployment_type=""
    # Confirmation vars will be set in cases after prompting
    CONFIRM_DOCKER_PUSH="n"; CONFIRM_TF_APPLY="n"; CONFIRM_TF_DESTROY="n"

    case $choice in
        1) # Update Local (Deploy Apache)
           deployment_type="local"
           echo "Starting local Apache deployment..."
           
           # Configure local deployment
           configure_deployment "$_GO_SCRIPT_DIR" "$deployment_type" || operation_failed=true
           
           if [ "$operation_failed" = false ]; then
               # Simple deployment for local - just need deployment name
               deployment_name="${CFG_DEPLOYMENT_NAME:-apache-local}"
               read -p "Enter deployment name [default: $deployment_name]: " input_name
               deployment_name="${input_name:-$deployment_name}"
               CFG_DEPLOYMENT_NAME="$deployment_name"  # Save for next time
               save_config  # Save the updated deployment name
               
               # Call simplified deploy function - 3 arguments: type, name, tf_confirm
               deploy "$deployment_type" "$deployment_name" "n" || operation_failed=true
           fi
           ;;
        2) # Update Remote (Deploy Apache to GCP)
           deployment_type="remote"
           echo "Starting remote Apache deployment to GCP..."
           
           # Configure remote deployment (this will prompt for SSL email, domain, etc.)
           configure_deployment "$_GO_SCRIPT_DIR" "$deployment_type" || operation_failed=true
           
           if [ "$operation_failed" = false ]; then
               # Simple deployment for remote - just need deployment name
               deployment_name="${CFG_DEPLOYMENT_NAME:-apache-remote}"
               read -p "Enter deployment name [default: $deployment_name]: " input_name
               deployment_name="${input_name:-$deployment_name}"
               CFG_DEPLOYMENT_NAME="$deployment_name"  # Save for next time
               save_config  # Save the updated deployment name
               
               # Use the tf_confirm from configuration
               tf_confirm="$CFG_CONFIRM_APPLY"
               
               # Call simplified deploy function - 3 arguments: type, name, tf_confirm
               deploy "$deployment_type" "$deployment_name" "$tf_confirm" || operation_failed=true
           fi
           ;;
        3) # Nuke Menu
            while true; do
                show_nuke_menu
                read -p "Nuke Menu - Enter choice [1-3]: " nuke_choice
                echo ""
                case $nuke_choice in
                    1) # Nuke Local
                        echo "Attempting to clean local Apache..."
                        # Call apache_nuke (ensure it is available, though it should be from utilities.sh)
                        if type apache_nuke &>/dev/null; then
                            apache_nuke || operation_failed=true
                        else
                            echo "Error: apache_nuke function not found." >&2
                            operation_failed=true
                        fi
                        break # Break from nuke menu loop
                        ;;
                    2) # Nuke Remote
                        echo "Attempting to destroy remote GCP infrastructure..."
                        # Prompt for Terraform destroy confirmation
                        read -p "Are you sure you want to destroy remote Terraform infrastructure? (y/n): " confirm_tf_destroy
                        confirm_tf_destroy="${confirm_tf_destroy:-n}"
                        
                        # Call terraform_destroy directly
                        if type terraform_destroy &>/dev/null; then
                            terraform_destroy "$confirm_tf_destroy" || operation_failed=true
                        else
                            echo "Error: terraform_destroy function not found." >&2
                            operation_failed=true
                        fi
                        break # Break from nuke menu loop
                        ;;
                    3) # Back to Main Menu
                        echo "Returning to main menu..."
                        break # Break from nuke menu loop
                        ;;
                    *)
                        echo "Invalid choice for Nuke Menu [1-3]." >&2
                        operation_failed=true
                        ;;
                esac
                if [[ "$nuke_choice" -ge 1 && "$nuke_choice" -le 3 ]]; then
                    break
                fi
            done
            ;;
        4) # Exit
           echo "Exiting."
           exit 0
           ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 4." >&2
            operation_failed=true
            ;;
    esac

    # Report if the chosen operation failed, except for invalid choice or exit
    if [ "$operation_failed" = true ] && [[ "$choice" -ge 1 && "$choice" -le 3 ]]; then # Adjusted range (1-3 for operations)
      echo "-------------------------"
      echo "Operation ($choice) failed. See messages above for details." >&2
      echo "-------------------------"
    fi

    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo ""
    clear
done 