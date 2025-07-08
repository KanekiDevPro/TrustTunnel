#!/bin/bash

# Define colors for better terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD_GREEN='\033[1;32m'
RESET='\033[0m' # No Color

# Global variables
RUST_IS_READY=false
CARGO_ENV_FILE="$HOME/.cargo/env"

# Function to draw a colored line for menu separation
draw_line() {
    local color="$1"
    local char="$2"
    local length=${3:-40} # Default length 40 if not provided
    printf "${color}"
    for ((i=0; i<length; i++)); do
        printf "$char"
    done
    printf "${RESET}\n"
}

# Function to print success messages in green
print_success() {
    local message="$1"
    echo -e "${GREEN}✅ $message${RESET}"
}

# Function to print error messages in red
print_error() {
    local message="$1"
    echo -e "${RED}❌ $message${RESET}"
}

# Function to print warning messages in yellow
print_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠️ $message${RESET}"
}

# Function to show service logs and return to menu
show_service_logs() {
    local service_name="$1"
    clear
    echo -e "${BLUE}--- Displaying logs for $service_name ---${RESET}"
    
    if systemctl is-active --quiet "$service_name"; then
        echo -e "${GREEN}Service Status: Active${RESET}"
    else
        echo -e "${RED}Service Status: Inactive${RESET}"
    fi
    echo ""
    
    # Display the last 50 lines of logs for the specified service
    sudo journalctl -u "$service_name" -n 50 --no-pager
    echo ""
    echo -e "${YELLOW}Press any key to return to the previous menu...${RESET}"
    read -n 1 -s -r
}

# Function to draw green line
draw_green_line() {
    echo -e "${GREEN}+--------------------------------------------------------+${RESET}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install system dependencies
install_dependencies() {
    echo -e "${CYAN}📦 Installing system dependencies...${RESET}"
    
    # Update package list
    if ! sudo apt update; then
        print_error "Failed to update package list"
        return 1
    fi
    
    # Install required packages
    local packages=(
        "build-essential"
        "curl"
        "pkg-config"
        "libssl-dev"
        "git"
        "figlet"
        "certbot"
        "wget"
        "tar"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            echo -e "${CYAN}Installing $package...${RESET}"
            if ! sudo apt install -y "$package"; then
                print_error "Failed to install $package"
                return 1
            fi
        else
            echo -e "${GREEN}$package is already installed${RESET}"
        fi
    done
    
    print_success "All dependencies installed successfully"
    return 0
}

# Function to install Rust
install_rust() {
    echo -e "${CYAN}🦀 Checking for Rust installation...${RESET}"
    
    if command_exists rustc && command_exists cargo; then
        print_success "Rust is already installed: $(rustc --version)"
        RUST_IS_READY=true
        return 0
    fi
    
    echo -e "${CYAN}Installing Rust...${RESET}"
    
    # Download and run the rustup installer
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
        print_success "Rust installed successfully"
        
        # Source the Cargo environment file
        if [ -f "$CARGO_ENV_FILE" ]; then
            source "$CARGO_ENV_FILE"
            echo -e "${CYAN}♻️ Cargo environment sourced${RESET}"
        else
            print_warning "Cargo environment file not found, setting PATH manually"
            export PATH="$HOME/.cargo/bin:$PATH"
        fi
        
        # Verify installation
        if command_exists rustc && command_exists cargo; then
            print_success "Installed Rust version: $(rustc --version)"
            RUST_IS_READY=true
            
            echo ""
            echo -e "${YELLOW}------------------------------------------------------------------${RESET}"
            echo -e "${YELLOW}⚠️ Important: To make Rust available in new terminal sessions,${RESET}"
            echo -e "${YELLOW}   restart your terminal or run: source \"$CARGO_ENV_FILE\"${RESET}"
            echo -e "${YELLOW}------------------------------------------------------------------${RESET}"
            
            return 0
        else
            print_error "Rust installation verification failed"
            return 1
        fi
    else
        print_error "Rust installation failed"
        return 1
    fi
}

# Function to uninstall TrustTunnel
uninstall_trusttunnel_action() {
    clear
    echo ""
    draw_line "$RED" "=" 40
    echo -e "${RED}        🗑️ Uninstall TrustTunnel${RESET}"
    draw_line "$RED" "=" 40
    echo ""
    
    echo -e "${RED}⚠️ Are you sure you want to uninstall TrustTunnel and remove all associated files and services?${RESET}"
    echo -e "${WHITE}This action cannot be undone! (y/N):${RESET} "
    read -r confirm
    echo ""
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}🧹 Uninstalling TrustTunnel...${RESET}"
        
        # Find and remove all trusttunnel services
        echo -e "${CYAN}🔍 Searching for TrustTunnel services...${RESET}"
        mapfile -t trusttunnel_services < <(sudo systemctl list-unit-files --full --no-pager | grep '^trusttunnel.*\.service' | awk '{print $1}')
        
        if [ ${#trusttunnel_services[@]} -gt 0 ]; then
            echo -e "${CYAN}🛑 Stopping and removing TrustTunnel services...${RESET}"
            for service_file in "${trusttunnel_services[@]}"; do
                local service_name=$(basename "$service_file")
                echo -e "  ${YELLOW}Processing $service_name...${RESET}"
                
                # Stop and disable service
                sudo systemctl stop "$service_name" 2>/dev/null || true
                sudo systemctl disable "$service_name" 2>/dev/null || true
                sudo rm -f "/etc/systemd/system/$service_name" 2>/dev/null || true
            done
            
            sudo systemctl daemon-reload
            print_success "All TrustTunnel services removed"
        else
            print_warning "No TrustTunnel services found"
        fi
        
        # Ask about closing firewall ports
        echo ""
        echo -e "${YELLOW}Do you want to close TrustTunnel ports in firewall? (y/N):${RESET} "
        read -r close_firewall_choice
        
        if [[ "$close_firewall_choice" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}🔥 Scanning for TrustTunnel ports to close...${RESET}"
            
            # Close common TrustTunnel ports
            local common_ports=("6060" "8800" "8801" "8802" "8803" "8804" "8805")
            for port in "${common_ports[@]}"; do
                close_firewall_port "$port" "both"
            done
            
            print_success "Common TrustTunnel ports closed in firewall"
        fi
        
        # Remove rstun folder
        if [ -d "rstun" ]; then
            echo -e "${CYAN}🗑️ Removing 'rstun' folder...${RESET}"
            rm -rf rstun
            print_success "'rstun' folder removed"
        else
            print_warning "'rstun' folder not found"
        fi
        
        print_success "TrustTunnel uninstallation complete"
    else
        print_warning "Uninstall cancelled"
    fi
    
    echo ""
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -r
}

# Function to install TrustTunnel
install_trusttunnel_action() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        📥 Installing TrustTunnel${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    # Remove existing rstun folder if it exists
    if [ -d "rstun" ]; then
        echo -e "${YELLOW}🧹 Removing existing 'rstun' folder...${RESET}"
        rm -rf rstun
        print_success "Existing 'rstun' folder removed"
    fi
    
    echo -e "${CYAN}🚀 Detecting system architecture...${RESET}"
    local arch=$(uname -m)
    local filename=""
    local supported_arch=true
    
    case "$arch" in
        "x86_64")
            filename="rstun-linux-x86_64.tar.gz"
            ;;
        "aarch64" | "arm64")
            filename="rstun-linux-aarch64.tar.gz"
            ;;
        "armv7l")
            filename="rstun-linux-armv7.tar.gz"
            ;;
        *)
            supported_arch=false
            print_error "Unsupported architecture detected: $arch"
            echo -e "${YELLOW}Do you want to try installing the x86_64 version as a fallback? (y/N):${RESET} "
            read -r fallback_confirm
            echo ""
            
            if [[ "$fallback_confirm" =~ ^[Yy]$ ]]; then
                filename="rstun-linux-x86_64.tar.gz"
                echo -e "${CYAN}Proceeding with x86_64 version as requested${RESET}"
            else
                print_warning "Installation cancelled"
                echo -e "${CYAN}Please download rstun manually from: https://github.com/neevek/rstun/releases${RESET}"
                echo ""
                echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
                read -r
                return 1
            fi
            ;;
    esac
    
    local download_url="https://github.com/neevek/rstun/releases/download/release%2F0.7.1/${filename}"
    
    echo -e "${CYAN}📥 Downloading $filename for $arch...${RESET}"
    if wget -q --show-progress "$download_url" -O "$filename"; then
        print_success "Download complete"
    else
        print_error "Failed to download $filename"
        echo ""
        echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
        read -r
        return 1
    fi
    
    echo -e "${CYAN}📦 Extracting files...${RESET}"
    if tar -xzf "$filename"; then
        # Rename extracted folder to 'rstun'
        mv "${filename%.tar.gz}" rstun 2>/dev/null || true
        print_success "Extraction complete"
    else
        print_error "Failed to extract $filename"
        rm -f "$filename"
        echo ""
        echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
        read -r
        return 1
    fi
    
    echo -e "${CYAN}➕ Setting execute permissions...${RESET}"
    find rstun -type f -exec chmod +x {} \; 2>/dev/null || true
    print_success "Permissions set"
    
    echo -e "${CYAN}🗑️ Cleaning up downloaded archive...${RESET}"
    rm -f "$filename"
    print_success "Cleanup complete"
    
    echo ""
    print_success "TrustTunnel installation complete!"
    echo ""
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -r
}

# Function to validate domain format
validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate email format
validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate port number
validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Function to detect firewall type
detect_firewall() {
    if command_exists ufw && ufw status >/dev/null 2>&1; then
        echo "ufw"
    elif command_exists iptables; then
        echo "iptables"
    else
        echo "none"
    fi
}

# Function to open port in firewall
open_firewall_port() {
    local port="$1"
    local protocol="$2"  # tcp, udp, or both
    local firewall_type=$(detect_firewall)
    
    case "$firewall_type" in
        "ufw")
            echo -e "${CYAN}🔥 Opening port $port ($protocol) in UFW firewall...${RESET}"
            case "$protocol" in
                "tcp")
                    sudo ufw allow "$port/tcp" >/dev/null 2>&1
                    ;;
                "udp")
                    sudo ufw allow "$port/udp" >/dev/null 2>&1
                    ;;
                "both")
                    sudo ufw allow "$port/tcp" >/dev/null 2>&1
                    sudo ufw allow "$port/udp" >/dev/null 2>&1
                    ;;
            esac
            print_success "Port $port ($protocol) opened in UFW"
            ;;
        "iptables")
            echo -e "${CYAN}🔥 Opening port $port ($protocol) in iptables firewall...${RESET}"
            case "$protocol" in
                "tcp")
                    sudo iptables -A INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1
                    ;;
                "udp")
                    sudo iptables -A INPUT -p udp --dport "$port" -j ACCEPT >/dev/null 2>&1
                    ;;
                "both")
                    sudo iptables -A INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1
                    sudo iptables -A INPUT -p udp --dport "$port" -j ACCEPT >/dev/null 2>&1
                    ;;
            esac
            
            # Save iptables rules
            if command_exists iptables-save && command_exists netfilter-persistent; then
                sudo netfilter-persistent save >/dev/null 2>&1
            elif [ -f /etc/iptables/rules.v4 ]; then
                sudo iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            fi
            
            print_success "Port $port ($protocol) opened in iptables"
            ;;
        "none")
            print_warning "No supported firewall detected (UFW/iptables)"
            ;;
    esac
}

# Function to close port in firewall
close_firewall_port() {
    local port="$1"
    local protocol="$2"  # tcp, udp, or both
    local firewall_type=$(detect_firewall)
    
    case "$firewall_type" in
        "ufw")
            echo -e "${CYAN}🔥 Closing port $port ($protocol) in UFW firewall...${RESET}"
            case "$protocol" in
                "tcp")
                    sudo ufw delete allow "$port/tcp" >/dev/null 2>&1
                    ;;
                "udp")
                    sudo ufw delete allow "$port/udp" >/dev/null 2>&1
                    ;;
                "both")
                    sudo ufw delete allow "$port/tcp" >/dev/null 2>&1
                    sudo ufw delete allow "$port/udp" >/dev/null 2>&1
                    ;;
            esac
            print_success "Port $port ($protocol) closed in UFW"
            ;;
        "iptables")
            echo -e "${CYAN}🔥 Closing port $port ($protocol) in iptables firewall...${RESET}"
            case "$protocol" in
                "tcp")
                    sudo iptables -D INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1
                    ;;
                "udp")
                    sudo iptables -D INPUT -p udp --dport "$port" -j ACCEPT >/dev/null 2>&1
                    ;;
                "both")
                    sudo iptables -D INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1
                    sudo iptables -D INPUT -p udp --dport "$port" -j ACCEPT >/dev/null 2>&1
                    ;;
            esac
            
            # Save iptables rules
            if command_exists iptables-save && command_exists netfilter-persistent; then
                sudo netfilter-persistent save >/dev/null 2>&1
            elif [ -f /etc/iptables/rules.v4 ]; then
                sudo iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            fi
            
            print_success "Port $port ($protocol) closed in iptables"
            ;;
        "none")
            print_warning "No supported firewall detected (UFW/iptables)"
            ;;
    esac
}

# Function to ask user about firewall configuration
ask_firewall_config() {
    local firewall_type=$(detect_firewall)
    
    if [ "$firewall_type" != "none" ]; then
        echo ""
        echo -e "${CYAN}🔥 Firewall Configuration:${RESET}"
        echo -e "${WHITE}Detected firewall: $firewall_type${RESET}"
        echo -e "${YELLOW}Do you want to automatically open the required ports in firewall? (Y/n):${RESET} "
        read -r firewall_choice
        
        if [[ "$firewall_choice" =~ ^[Nn]$ ]]; then
            return 1  # User chose not to configure firewall
        else
            return 0  # User chose to configure firewall
        fi
    else
        print_warning "No supported firewall detected. Skipping firewall configuration."
        return 1
    fi
}

# Function to add new server
add_new_server_action() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        ➕ Add New TrustTunnel Server${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    # Check if rstund exists
    if [ ! -f "rstun/rstund" ]; then
        print_error "Server build (rstun/rstund) not found"
        echo -e "${YELLOW}Please run 'Install TrustTunnel' option from the main menu first${RESET}"
        echo ""
        echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
        read -r
        return
    fi
    
    # Get domain with validation
    while true; do
        echo -e "${CYAN}🌐 Domain Configuration:${RESET}"
        echo -e "  ${WHITE}Enter your domain (e.g., server.example.com):${RESET} "
        read -r domain
        
        if [ -z "$domain" ]; then
            print_error "Domain cannot be empty"
            continue
        fi
        
        if validate_domain "$domain"; then
            break
        else
            print_error "Invalid domain format"
        fi
    done
    
    # Get email with validation
    while true; do
        echo ""
        echo -e "${WHITE}Enter your email for SSL certificate:${RESET} "
        read -r email
        
        if [ -z "$email" ]; then
            print_error "Email cannot be empty"
            continue
        fi
        
        if validate_email "$email"; then
            break
        else
            print_error "Invalid email format"
        fi
    done
    
    echo ""
    local cert_path="/etc/letsencrypt/live/$domain"
    
    # Check for existing SSL certificate
    if [ -d "$cert_path" ]; then
        print_success "SSL certificate for $domain already exists"
    else
        echo -e "${CYAN}🔐 Requesting SSL certificate with Certbot...${RESET}"
        if sudo certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m "$email"; then
            print_success "SSL certificate obtained successfully"
        else
            print_error "Failed to obtain SSL certificate"
            echo ""
            echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
            read -r
            return
        fi
    fi
    
    # Get server configuration with validation
    echo ""
    echo -e "${CYAN}⚙️ Server Configuration:${RESET}"
    
    # Listen port
    while true; do
        echo -e "${WHITE}Enter tunneling address port (default: 6060):${RESET} "
        read -r listen_port
        listen_port=${listen_port:-6060}
        
        if validate_port "$listen_port"; then
            break
        else
            print_error "Invalid port number (1-65535)"
        fi
    done
    
    # TCP upstream port
    while true; do
        echo -e "${WHITE}Enter TCP upstream port (default: 8800):${RESET} "
        read -r tcp_upstream_port
        tcp_upstream_port=${tcp_upstream_port:-8800}
        
        if validate_port "$tcp_upstream_port"; then
            break
        else
            print_error "Invalid port number (1-65535)"
        fi
    done
    
    # UDP upstream port
    while true; do
        echo -e "${WHITE}Enter UDP upstream port (default: 8800):${RESET} "
        read -r udp_upstream_port
        udp_upstream_port=${udp_upstream_port:-8800}
        
        if validate_port "$udp_upstream_port"; then
            break
        else
            print_error "Invalid port number (1-65535)"
        fi
    done
    
    # Password
    while true; do
        echo -e "${WHITE}Enter password:${RESET} "
        read -r password
        
        if [ -n "$password" ]; then
            break
        else
            print_error "Password cannot be empty"
        fi
    done
    
    # Ask about firewall configuration
    local configure_firewall=false
    if ask_firewall_config; then
        configure_firewall=true
        
        # Open listen port
        open_firewall_port "$listen_port" "tcp"
        
        # Open upstream ports if different from listen port
        if [ "$tcp_upstream_port" != "$listen_port" ]; then
            open_firewall_port "$tcp_upstream_port" "tcp"
        fi
        
        if [ "$udp_upstream_port" != "$listen_port" ] && [ "$udp_upstream_port" != "$tcp_upstream_port" ]; then
            open_firewall_port "$udp_upstream_port" "udp"
        fi
    fi
    
    echo ""
    
    # Stop existing service if running
    local service_file="/etc/systemd/system/trusttunnel.service"
    if systemctl is-active --quiet trusttunnel.service || systemctl is-enabled --quiet trusttunnel.service; then
        echo -e "${YELLOW}🛑 Stopping existing TrustTunnel service...${RESET}"
        sudo systemctl stop trusttunnel.service 2>/dev/null || true
        sudo systemctl disable trusttunnel.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/trusttunnel.service 2>/dev/null || true
        sudo systemctl daemon-reload
        print_success "Existing TrustTunnel service removed"
    fi
    
    # Create systemd service file
    cat <<EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=TrustTunnel Server Service
After=network.target

[Service]
Type=simple
ExecStart=$(pwd)/rstun/rstund --addr 0.0.0.0:$listen_port --tcp-upstream $tcp_upstream_port --udp-upstream $udp_upstream_port --password "$password" --cert "$cert_path/fullchain.pem" --key "$cert_path/privkey.pem"
Restart=always
RestartSec=5
User=$(whoami)
WorkingDirectory=$(pwd)

[Install]
WantedBy=multi-user.target
EOF
    
    echo -e "${CYAN}🔧 Configuring systemd service...${RESET}"
    sudo systemctl daemon-reload
    
    echo -e "${CYAN}🚀 Starting TrustTunnel service...${RESET}"
    if sudo systemctl enable trusttunnel.service && sudo systemctl start trusttunnel.service; then
        print_success "TrustTunnel service started successfully!"
        
        # Show service status
        echo ""
        echo -e "${CYAN}📊 Service Status:${RESET}"
        sudo systemctl status trusttunnel.service --no-pager -l
    else
        print_error "Failed to start TrustTunnel service"
    fi
    
    echo ""
    echo -e "${YELLOW}Do you want to view the logs now? (y/N):${RESET} "
    read -r view_logs_choice
    
    if [[ "$view_logs_choice" =~ ^[Yy]$ ]]; then
        show_service_logs "trusttunnel.service"
    fi
    
    echo ""
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -r
}

# Function to add new client
add_new_client_action() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        ➕ Add New TrustTunnel Client${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    # Check if rstunc exists
    if [ ! -f "rstun/rstunc" ]; then
        print_error "Client build (rstun/rstunc) not found"
        echo -e "${YELLOW}Please run 'Install TrustTunnel' option from the main menu first${RESET}"
        echo ""
        echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
        read -r
        return
    fi
    
    # Get client name with validation
    while true; do
        echo -e "${WHITE}Enter client name (e.g., asiatech, respina, server2):${RESET} "
        read -r client_name
        
        if [ -z "$client_name" ]; then
            print_error "Client name cannot be empty"
            continue
        fi
        
        # Check if service already exists
        local service_name="trusttunnel-$client_name"
        local service_file="/etc/systemd/system/${service_name}.service"
        
        if [ -f "$service_file" ]; then
            print_error "Service with this name already exists"
            continue
        fi
        
        break
    done
    
    echo ""
    
    # Get server address with validation
    while true; do
        echo -e "${CYAN}🌐 Server Connection Details:${RESET}"
        echo -e "${WHITE}Server address and port (e.g., server.yourdomain.com:6060):${RESET} "
        read -r server_addr
        
        if [ -z "$server_addr" ]; then
            print_error "Server address cannot be empty"
            continue
        fi
        
        # Basic validation for address:port format
        if [[ "$server_addr" =~ ^[^:]+:[0-9]+$ ]]; then
            break
        else
            print_error "Invalid format. Use: domain:port or ip:port"
        fi
    done

    # Extract server port from server address
    local server_port=""
    if [[ "$server_addr" =~ :([0-9]+)$ ]]; then
        server_port="${BASH_REMATCH[1]}"
    fi

    echo ""
    
    # Get tunnel mode
    while true; do
        echo -e "${CYAN}📡 Tunnel Mode:${RESET}"
        echo -e "${WHITE}Select tunnel mode:${RESET}"
        echo -e "  ${YELLOW}1)${RESET} TCP only"
        echo -e "  ${YELLOW}2)${RESET} UDP only"
        echo -e "  ${YELLOW}3)${RESET} Both TCP and UDP"
        echo -e "${WHITE}Your choice (1-3):${RESET} "
        read -r mode_choice
        
        case "$mode_choice" in
            1)
                tunnel_mode="tcp"
                break
                ;;
            2)
                tunnel_mode="udp"
                break
                ;;
            3)
                tunnel_mode="both"
                break
                ;;
            *)
                print_error "Invalid choice. Please select 1, 2, or 3"
                ;;
        esac
    done
    
    echo ""
    
    # Get password
    while true; do
        echo -e "${WHITE}Enter password:${RESET} "
        read -r password
        
        if [ -n "$password" ]; then
            break
        else
            print_error "Password cannot be empty"
        fi
    done
    
    echo ""
    
    # Get port mappings
    while true; do
        echo -e "${CYAN}🔢 Port Mapping Configuration:${RESET}"
        echo -e "${WHITE}How many ports to tunnel?${RESET} "
        read -r port_count
        
        if [[ "$port_count" =~ ^[0-9]+$ ]] && [ "$port_count" -gt 0 ] && [ "$port_count" -le 100 ]; then
            break
        else
            print_error "Invalid number. Please enter a number between 1 and 100"
        fi
    done
    
    echo ""
    
    # Collect port mappings
    local mappings=""
    for ((i=1; i<=port_count; i++)); do
        while true; do
            echo -e "${WHITE}Port #$i:${RESET} "
            read -r port
            
            if validate_port "$port"; then
                local mapping="IN^0.0.0.0:$port^0.0.0.0:$port"
                if [ -z "$mappings" ]; then
                    mappings="$mapping"
                else
                    mappings="$mappings,$mapping"
                fi
                break
            else
                print_error "Invalid port number (1-65535)"
            fi
        done
    done
    
    # Ask about firewall configuration
    local configure_firewall=false
    if ask_firewall_config; then
        configure_firewall=true
        
        # Extract ports from mappings and open them
        echo -e "${CYAN}🔥 Opening client ports in firewall...${RESET}"
        IFS=',' read -ra MAPPING_ARRAY <<< "$mappings"
        for mapping in "${MAPPING_ARRAY[@]}"; do
            # Extract port from mapping format: IN^0.0.0.0:PORT^0.0.0.0:PORT
            local port=$(echo "$mapping" | cut -d'^' -f2 | cut -d':' -f2)
            
            case "$tunnel_mode" in
                "tcp")
                    open_firewall_port "$port" "tcp"
                    ;;
                "udp")
                    open_firewall_port "$port" "udp"
                    ;;
                "both")
                    open_firewall_port "$port" "both"
                    ;;
            esac
        done

        # Also open server connection port if it's not standard
        if [ -n "$server_port" ] && [ "$server_port" != "80" ] && [ "$server_port" != "443" ]; then
            echo -e "${CYAN}🔥 Opening server connection port in firewall...${RESET}"
            open_firewall_port "$server_port" "tcp"
        fi
    fi

    echo ""
    
    # Determine mapping arguments based on tunnel mode
    local mapping_args=""
    case "$tunnel_mode" in
        "tcp")
            mapping_args="--tcp-mappings \"$mappings\""
            ;;
        "udp")
            mapping_args="--udp-mappings \"$mappings\""
            ;;
        "both")
            mapping_args="--tcp-mappings \"$mappings\" --udp-mappings \"$mappings\""
            ;;
    esac
    
    # Create systemd service file
    cat <<EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=TrustTunnel Client - $client_name
After=network.target

[Service]
Type=simple
ExecStart=$(pwd)/rstun/rstunc --server-addr "$server_addr" --password "$password" $mapping_args
Restart=always
RestartSec=5
User=$(whoami)
WorkingDirectory=$(pwd)

[Install]
WantedBy=multi-user.target
EOF
    
    echo -e "${CYAN}🔧 Configuring systemd service...${RESET}"
    sudo systemctl daemon-reload
    
    echo -e "${CYAN}🚀 Starting TrustTunnel client service...${RESET}"
    if sudo systemctl enable "$service_name" && sudo systemctl start "$service_name"; then
        print_success "Client '$client_name' started as $service_name"
        
        # Show service status
        echo ""
        echo -e "${CYAN}📊 Service Status:${RESET}"
        sudo systemctl status "$service_name" --no-pager -l
    else
        print_error "Failed to start client service"
    fi
    
    echo ""
    echo -e "${YELLOW}Do you want to view the logs now? (y/N):${RESET} "
    read -r view_logs_choice
    
    if [[ "$view_logs_choice" =~ ^[Yy]$ ]]; then
        show_service_logs "$service_name"
    fi
    
    echo ""
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -r
}

# Function to show client logs menu
show_client_logs_menu() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        📊 TrustTunnel Client Logs${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    echo -e "${CYAN}🔍 Searching for client services...${RESET}"
    mapfile -t services < <(systemctl list-units --type=service --all | grep 'trusttunnel-' | awk '{print $1}' | sed 's/.service$//')
    
    if [ ${#services[@]} -eq 0 ]; then
        print_error "No client services found"
        echo ""
        echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
        read -r
        return
    fi
    
    echo -e "${CYAN}📋 Available client services:${RESET}"
    for i in "${!services[@]}"; do
        echo -e "  ${YELLOW}$((i+1)))${RESET} ${services[i]}"
    done
    echo ""
    
    while true; do
        echo -e "${WHITE}Select a service to view logs (1-${#services[@]}):${RESET} "
        read -r selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#services[@]} ]; then
            local selected_service="${services[$((selection-1))]}"
            show_service_logs "$selected_service"
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and ${#services[@]}"
        fi
    done
}

# Function to delete client menu
delete_client_menu() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        🗑️ Delete TrustTunnel Client${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    echo -e "${CYAN}🔍 Searching for client services...${RESET}"
    mapfile -t services < <(systemctl list-units --type=service --all | grep 'trusttunnel-' | awk '{print $1}' | sed 's/.service$//')
    
    if [ ${#services[@]} -eq 0 ]; then
        print_error "No client services found"
        echo ""
        echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
        read -r
        return
    fi
    
    echo -e "${CYAN}📋 Available client services:${RESET}"
    for i in "${!services[@]}"; do
        echo -e "  ${YELLOW}$((i+1)))${RESET} ${services[i]}"
    done
    echo ""
    
    while true; do
        echo -e "${WHITE}Select a service to delete (1-${#services[@]}):${RESET} "
        read -r selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#services[@]} ]; then
            local selected_service="${services[$((selection-1))]}"
            local service_file="/etc/systemd/system/${selected_service}.service"
            
            echo ""
            echo -e "${RED}⚠️ Are you sure you want to delete '$selected_service'? (y/N):${RESET} "
            read -r confirm
            
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}🛑 Stopping $selected_service...${RESET}"
                sudo systemctl stop "$selected_service" 2>/dev/null || true
                
                echo -e "${YELLOW}🗑️ Disabling $selected_service...${RESET}"
                sudo systemctl disable "$selected_service" 2>/dev/null || true
                
                echo -e "${YELLOW}🗑️ Removing service file...${RESET}"
                sudo rm -f "$service_file" 2>/dev/null || true
                
                sudo systemctl daemon-reload
                print_success "Client '$selected_service' deleted successfully"
                
                # Ask about closing firewall ports
                echo ""
                echo -e "${YELLOW}Do you want to close the client ports in firewall? (y/N):${RESET} "
                read -r close_ports_choice

                if [[ "$close_ports_choice" =~ ^[Yy]$ ]]; then
                    # Extract ports from service file content before it was deleted
                    local service_content=$(sudo systemctl cat "$selected_service" 2>/dev/null || echo "")
                    
                    if [ -n "$service_content" ]; then
                        # Extract TCP mappings
                        local tcp_mappings=$(echo "$service_content" | grep -o '\--tcp-mappings "[^"]*"' | sed 's/--tcp-mappings "//;s/"//')
                        # Extract UDP mappings  
                        local udp_mappings=$(echo "$service_content" | grep -o '\--udp-mappings "[^"]*"' | sed 's/--udp-mappings "//;s/"//')
                        
                        # Close TCP ports
                        if [ -n "$tcp_mappings" ]; then
                            IFS=',' read -ra TCP_ARRAY <<< "$tcp_mappings"
                            for mapping in "${TCP_ARRAY[@]}"; do
                                local port=$(echo "$mapping" | cut -d'^' -f2 | cut -d':' -f2)
                                close_firewall_port "$port" "tcp"
                            done
                        fi
                        
                        # Close UDP ports
                        if [ -n "$udp_mappings" ]; then
                            IFS=',' read -ra UDP_ARRAY <<< "$udp_mappings"
                            for mapping in "${UDP_ARRAY[@]}"; do
                                local port=$(echo "$mapping" | cut -d'^' -f2 | cut -d':' -f2)
                                close_firewall_port "$port" "udp"
                            done
                        fi
                        
                        print_success "Client ports closed in firewall"
                    else
                        print_warning "Could not extract port information to close firewall ports"
                    fi
                fi
            else
                print_warning "Deletion cancelled"
            fi
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and ${#services[@]}"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -r
}

# Function to show server status
show_server_status() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        📊 TrustTunnel Server Status${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    local service_file="/etc/systemd/system/trusttunnel.service"
    
    if [ -f "$service_file" ]; then
        echo -e "${CYAN}🔍 Service Information:${RESET}"
        echo -e "${WHITE}Service Name: trusttunnel.service${RESET}"
        echo ""
        
        # Check service status
        if systemctl is-active --quiet trusttunnel.service; then
            echo -e "${GREEN}🟢 Status: Active (Running)${RESET}"
        else
            echo -e "${RED}🔴 Status: Inactive (Stopped)${RESET}"
        fi
        
        if systemctl is-enabled --quiet trusttunnel.service; then
            echo -e "${GREEN}🟢 Enabled: Yes (Auto-start on boot)${RESET}"
        else
            echo -e "${YELLOW}🟡 Enabled: No (Manual start only)${RESET}"
        fi
        
        echo ""
        echo -e "${CYAN}📋 Detailed Status:${RESET}"
        sudo systemctl status trusttunnel.service --no-pager -l
        
        echo ""
        echo -e "${CYAN}🔧 Service Configuration:${RESET}"
        
        # Extract configuration from service file
        local exec_start=$(grep "ExecStart=" "$service_file" | cut -d'=' -f2-)
        if [ -n "$exec_start" ]; then
            echo -e "${WHITE}Command: $exec_start${RESET}"
            
            # Extract ports from command - اصلاح regex ها
            local listen_port=$(echo "$exec_start" | grep -o '\--addr [^:]*:[0-9]*' | cut -d':' -f2)
            local tcp_port=$(echo "$exec_start" | grep -o '\--tcp-upstream [0-9]*' | awk '{print $2}')
            local udp_port=$(echo "$exec_start" | grep -o '\--udp-upstream [0-9]*' | awk '{print $2}')
            
            echo ""
            echo -e "${CYAN}🔌 Port Configuration:${RESET}"
            [ -n "$listen_port" ] && echo -e "${WHITE}Listen Port: $listen_port${RESET}"
            [ -n "$tcp_port" ] && echo -e "${WHITE}TCP Upstream: $tcp_port${RESET}"
            [ -n "$udp_port" ] && echo -e "${WHITE}UDP Upstream: $udp_port${RESET}"
        fi
        
        echo ""
        echo -e "${CYAN}🔥 Firewall Status:${RESET}"
        check_firewall_ports "$listen_port" "$tcp_port" "$udp_port"
        
    else
        print_error "Server service not found"
        echo -e "${YELLOW}No TrustTunnel server is configured${RESET}"
    fi
    
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -r
}

# Function to show client status
show_client_status() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        📊 TrustTunnel Client Status${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    echo -e "${CYAN}🔍 Searching for client services...${RESET}"
    mapfile -t services < <(systemctl list-units --type=service --all | grep 'trusttunnel-' | awk '{print $1}' | sed 's/.service$//')
    
    if [ ${#services[@]} -eq 0 ]; then
        print_error "No client services found"
        echo -e "${YELLOW}No TrustTunnel clients are configured${RESET}"
    else
        echo -e "${CYAN}📋 Client Services Overview:${RESET}"
        echo ""
        
        for service in "${services[@]}"; do
            echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            echo -e "${CYAN}🔧 Service: $service${RESET}"
            
            # Check service status
            if systemctl is-active --quiet "$service"; then
                echo -e "${GREEN}🟢 Status: Active (Running)${RESET}"
            else
                echo -e "${RED}🔴 Status: Inactive (Stopped)${RESET}"
            fi
            
            if systemctl is-enabled --quiet "$service"; then
                echo -e "${GREEN}🟢 Enabled: Yes${RESET}"
            else
                echo -e "${YELLOW}🟡 Enabled: No${RESET}"
            fi
            
            # Extract configuration
            local service_file="/etc/systemd/system/${service}.service"
            if [ -f "$service_file" ]; then
                local exec_start=$(grep "ExecStart=" "$service_file" | cut -d'=' -f2-)
                
                # Extract server address - حذف کوتیشن‌های اضافی
                local server_addr=$(echo "$exec_start" | grep -o '\--server-addr [^ ]*' | cut -d' ' -f2 | sed 's/"//g')
                [ -n "$server_addr" ] && echo -e "${WHITE}🌐 Server: $server_addr${RESET}"
                
                # Extract mappings - اصلاح نمایش پورت‌ها
                local tcp_mappings=$(echo "$exec_start" | grep -o '\--tcp-mappings "[^"]*"' | sed 's/--tcp-mappings "//;s/"//')
                local udp_mappings=$(echo "$exec_start" | grep -o '\--udp-mappings "[^"]*"' | sed 's/--udp-mappings "//;s/"//')

                if [ -n "$tcp_mappings" ]; then
                    # استخراج پورت‌ها از فرمت IN^0.0.0.0:PORT^0.0.0.0:PORT
                    local tcp_ports=$(echo "$tcp_mappings" | sed 's/IN\^0\.0\.0\.0://g' | sed 's/\^0\.0\.0\.0:[0-9]*//g' | tr ',' ' ')
                    echo -e "${WHITE}🔌 TCP Ports: $tcp_ports${RESET}"
                fi

                if [ -n "$udp_mappings" ]; then
                    local udp_ports=$(echo "$udp_mappings" | sed 's/IN\^0\.0\.0\.0://g' | sed 's/\^0\.0\.0\.0:[0-9]*//g' | tr ',' ' ')
                    echo -e "${WHITE}🔌 UDP Ports: $udp_ports${RESET}"
                fi
            fi
            echo ""
        done
        
        echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo ""
        echo -e "${CYAN}📊 Summary:${RESET}"
        
        local active_count=0
        local total_count=${#services[@]}
        
        for service in "${services[@]}"; do
            if systemctl is-active --quiet "$service"; then
                ((active_count++))
            fi
        done
        
        echo -e "${WHITE}Total Clients: $total_count${RESET}"
        echo -e "${GREEN}Active Clients: $active_count${RESET}"
        echo -e "${RED}Inactive Clients: $((total_count - active_count))${RESET}"
    fi
    
    echo ""
    echo -e "${YELLOW}Press Enter to return to previous menu...${RESET}"
    read -r
}

# Function to check firewall ports status
check_firewall_ports() {
    local listen_port="$1"
    local tcp_port="$2"
    local udp_port="$3"
    local firewall_type=$(detect_firewall)
    
    case "$firewall_type" in
        "ufw")
            echo -e "${WHITE}Firewall Type: UFW${RESET}"
            
            if [ -n "$listen_port" ]; then
                if sudo ufw status | grep -q "$listen_port/tcp"; then
                    echo -e "${GREEN}🟢 Port $listen_port/tcp: Open${RESET}"
                else
                    echo -e "${RED}🔴 Port $listen_port/tcp: Closed${RESET}"
                fi
            fi
            
            if [ -n "$tcp_port" ] && [ "$tcp_port" != "$listen_port" ]; then
                if sudo ufw status | grep -q "$tcp_port/tcp"; then
                    echo -e "${GREEN}🟢 Port $tcp_port/tcp: Open${RESET}"
                else
                    echo -e "${RED}🔴 Port $tcp_port/tcp: Closed${RESET}"
                fi
            fi
            
            if [ -n "$udp_port" ] && [ "$udp_port" != "$listen_port" ] && [ "$udp_port" != "$tcp_port" ]; then
                if sudo ufw status | grep -q "$udp_port/udp"; then
                    echo -e "${GREEN}🟢 Port $udp_port/udp: Open${RESET}"
                else
                    echo -e "${RED}🔴 Port $udp_port/udp: Closed${RESET}"
                fi
            fi
            ;;
        "iptables")
            echo -e "${WHITE}Firewall Type: iptables${RESET}"
            
            if [ -n "$listen_port" ]; then
                if sudo iptables -L INPUT -n | grep -q "dpt:$listen_port"; then
                    echo -e "${GREEN}🟢 Port $listen_port: Open${RESET}"
                else
                    echo -e "${RED}🔴 Port $listen_port: Closed${RESET}"
                fi
            fi
            ;;
        "none")
            echo -e "${YELLOW}🟡 No firewall detected${RESET}"
            ;;
    esac
}

# Function to show all services status
show_all_services_status() {
    clear
    echo ""
    draw_line "$CYAN" "=" 50
    echo -e "${CYAN}        📊 All TrustTunnel Services Status${RESET}"
    draw_line "$CYAN" "=" 50
    echo ""
    
    # Check server
    echo -e "${CYAN}🖥️ SERVER STATUS:${RESET}"
    local server_service="/etc/systemd/system/trusttunnel.service"
    if [ -f "$server_service" ]; then
        if systemctl is-active --quiet trusttunnel.service; then
            echo -e "${GREEN}🟢 trusttunnel.service: Active${RESET}"
        else
            echo -e "${RED}🔴 trusttunnel.service: Inactive${RESET}"
        fi
    else
        echo -e "${YELLOW}🟡 No server configured${RESET}"
    fi
    
    echo ""
    
    # Check clients
    echo -e "${CYAN}💻 CLIENT STATUS:${RESET}"
    mapfile -t client_services < <(systemctl list-units --type=service --all | grep 'trusttunnel-' | awk '{print $1}' | sed 's/.service$//')
    
    if [ ${#client_services[@]} -eq 0 ]; then
        echo -e "${YELLOW}🟡 No clients configured${RESET}"
    else
        for service in "${client_services[@]}"; do
            if systemctl is-active --quiet "$service"; then
                echo -e "${GREEN}🟢 $service: Active${RESET}"
            else
                echo -e "${RED}🔴 $service: Inactive${RESET}"
            fi
        done
    fi
    
    echo ""
    echo -e "${CYAN}📊 SUMMARY:${RESET}"
    
    local total_services=0
    local active_services=0
    
    # Count server
    if [ -f "$server_service" ]; then
        ((total_services++))
        if systemctl is-active --quiet trusttunnel.service; then
            ((active_services++))
        fi
    fi
    
    # Count clients
    for service in "${client_services[@]}"; do
        ((total_services++))
        if systemctl is-active --quiet "$service"; then
            ((active_services++))
        fi
    done
    
    echo -e "${WHITE}Total Services: $total_services${RESET}"
    echo -e "${GREEN}Active Services: $active_services${RESET}"
    echo -e "${RED}Inactive Services: $((total_services - active_services))${RESET}"
    
    echo ""
    echo -e "${YELLOW}Press Enter to return to main menu...${RESET}"
    read -r
}

# Function to show server management menu
server_management_menu() {
    while true; do
        clear
        echo ""
        draw_line "$GREEN" "=" 40
        echo -e "${CYAN}        🔧 TrustTunnel Server Management${RESET}"
        draw_line "$GREEN" "=" 40
        echo ""
        echo -e "  ${YELLOW}1)${RESET} ${WHITE}Add new server${RESET}"
        echo -e "  ${YELLOW}2)${RESET} ${WHITE}Show service logs${RESET}"
        echo -e "  ${YELLOW}3)${RESET} ${WHITE}Show service status${RESET}"
        echo -e "  ${YELLOW}4)${RESET} ${WHITE}Delete service${RESET}"
        echo -e "  ${YELLOW}5)${RESET} ${WHITE}Back to main menu${RESET}"
        echo ""
        draw_line "$GREEN" "-" 40
        echo -e "${WHITE}Your choice:${RESET} "
        read -r srv_choice
        echo ""
        
        case $srv_choice in
            1)
                add_new_server_action
                ;;
            2)
                local service_file="/etc/systemd/system/trusttunnel.service"
                if [ -f "$service_file" ]; then
                    show_service_logs "trusttunnel.service"
                else
                    print_error "Service 'trusttunnel.service' not found"
                    echo ""
                    echo -e "${YELLOW}Press Enter to continue...${RESET}"
                    read -r
                fi
                ;;
            3)
                show_server_status
                ;;
            4)
                local service_file="/etc/systemd/system/trusttunnel.service"
                if [ -f "$service_file" ]; then
                    echo -e "${RED}⚠️ Are you sure you want to delete the server service? (y/N):${RESET} "
                    read -r confirm
                    
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        echo -e "${YELLOW}🛑 Stopping trusttunnel.service...${RESET}"
                        sudo systemctl stop trusttunnel.service 2>/dev/null || true
                        sudo systemctl disable trusttunnel.service 2>/dev/null || true
                        sudo rm -f "$service_file" 2>/dev/null || true
                        sudo systemctl daemon-reload
                        print_success "Server service deleted"
                        
                        # Ask about closing firewall ports
                        echo ""
                        echo -e "${YELLOW}Do you want to close the server ports in firewall? (y/N):${RESET} "
                        read -r close_ports_choice
                        
                        if [[ "$close_ports_choice" =~ ^[Yy]$ ]]; then
                            # Try to extract ports from service file before deletion
                            if [ -f "$service_file" ]; then
                                local listen_port=$(grep -o '\--addr [^:]*:$$[0-9]*$$' "$service_file" | cut -d':' -f2 || echo "6060")
                                local tcp_port=$(grep -o '\--tcp-upstream $$[0-9]*$$' "$service_file" | awk '{print $2}' || echo "8800")
                                local udp_port=$(grep -o '\--udp-upstream $$[0-9]*$$' "$service_file" | awk '{print $2}' || echo "8800")
                                
                                close_firewall_port "$listen_port" "tcp"
                                if [ "$tcp_port" != "$listen_port" ]; then
                                    close_firewall_port "$tcp_port" "tcp"
                                fi
                                if [ "$udp_port" != "$listen_port" ] && [ "$udp_port" != "$tcp_port" ]; then
                                    close_firewall_port "$udp_port" "udp"
                                fi
                            fi
                        fi
                    else
                        print_warning "Deletion cancelled"
                    fi
                else
                    print_error "Service 'trusttunnel.service' not found"
                fi
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            5)
                break
                ;;
            *)
                print_error "Invalid option"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
        esac
    done
}

# Function to show client management menu
client_management_menu() {
    while true; do
        clear
        echo ""
        draw_line "$GREEN" "=" 40
        echo -e "${CYAN}        📡 TrustTunnel Client Management${RESET}"
        draw_line "$GREEN" "=" 40
        echo ""
        echo -e "  ${YELLOW}1)${RESET} ${WHITE}Add new client${RESET}"
        echo -e "  ${YELLOW}2)${RESET} ${WHITE}Show client logs${RESET}"
        echo -e "  ${YELLOW}3)${RESET} ${WHITE}Show client status${RESET}"
        echo -e "  ${YELLOW}4)${RESET} ${WHITE}Delete a client${RESET}"
        echo -e "  ${YELLOW}5)${RESET} ${WHITE}Back to main menu${RESET}"
        echo ""
        draw_line "$GREEN" "-" 40
        echo -e "${WHITE}Your choice:${RESET} "
        read -r client_choice
        echo ""
        
        case $client_choice in
            1)
                add_new_client_action
                ;;
            2)
                show_client_logs_menu
                ;;
            3)
                show_client_status
                ;;
            4)
                delete_client_menu
                ;;
            5)
                break
                ;;
            *)
                print_error "Invalid option"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
        esac
    done
}

# Function to show tunnel management menu
tunnel_management_menu() {
    while true; do
        clear
        echo ""
        draw_line "$GREEN" "=" 40
        echo -e "${CYAN}        🌐 Choose Tunnel Mode${RESET}"
        draw_line "$GREEN" "=" 40
        echo ""
        echo -e "  ${YELLOW}1)${RESET} ${MAGENTA}Server (Iran)${RESET}"
        echo -e "  ${YELLOW}2)${RESET} ${BLUE}Client (Kharej)${RESET}"
        echo -e "  ${YELLOW}3)${RESET} ${WHITE}Return to main menu${RESET}"
        echo ""
        draw_line "$GREEN" "-" 40
        echo -e "${WHITE}Your choice:${RESET} "
        read -r tunnel_choice
        echo ""
        
        case $tunnel_choice in
            1)
                server_management_menu
                ;;
            2)
                client_management_menu
                ;;
            3)
                break
                ;;
            *)
                print_error "Invalid option"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
        esac
    done
}

# Main function
main() {
    # Set error handling
    set -e
    
    # Install dependencies
    if ! install_dependencies; then
        print_error "Failed to install dependencies"
        exit 1
    fi
    
    # Install Rust
    if ! install_rust; then
        print_error "Failed to install Rust"
        exit 1
    fi
    
    # Check if Rust is ready
    if [ "$RUST_IS_READY" != true ]; then
        print_error "Rust is not ready. Cannot continue"
        exit 1
    fi
    
    # Main menu loop
    while true; do
        clear
        echo -e "${CYAN}"
        if command_exists figlet; then
            figlet -f slant "TrustTunnel" 2>/dev/null || echo "TrustTunnel"
        else
            echo "TrustTunnel"
        fi
        echo -e "${RESET}"
        
        echo -e "${YELLOW}==========================================================${RESET}"
        echo -e "${YELLOW}Developed by ErfanXRay => https://github.com/Erfan-XRay/TrustTunnel${RESET}"
        echo -e "${YELLOW}Telegram Channel => @Erfan_XRay${RESET}"
        echo -e "${WHITE}Reverse tunnel over QUIC (Based on rstun project)${RESET}"
        
        draw_green_line
        echo -e "${GREEN}|${RESET}              ${BOLD_GREEN}TrustTunnel Main Menu${RESET}                  ${GREEN}|${RESET}"
        draw_green_line
        
        echo ""
        echo -e "${WHITE}Select an option:${RESET}"
        echo -e "${MAGENTA}1) Install TrustTunnel${RESET}"
        echo -e "${CYAN}2) Tunnel Management${RESET}"
        echo -e "${BLUE}3) Service Status${RESET}"
        echo -e "${GREEN}4) Advanced Management${RESET}"
        echo -e "${RED}5) Uninstall TrustTunnel${RESET}"
        echo -e "${WHITE}6) Exit${RESET}"
        echo ""
        echo -e "${WHITE}Your choice:${RESET} "
        read -r choice
        
        case $choice in
            1)
                install_trusttunnel_action
                ;;
            2)
                tunnel_management_menu
                ;;
            3)
                show_all_services_status
                ;;
            4)
                advanced_management_menu
                ;;
            5)
                uninstall_trusttunnel_action
                ;;
            6)
                echo -e "${GREEN}👋 Goodbye!${RESET}"
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
        esac
    done
}

# Function to setup SSL certificate auto-renewal
setup_ssl_renewal() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        🔐 SSL Certificate Auto-Renewal${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    echo -e "${CYAN}🔍 Checking existing SSL certificates...${RESET}"
    local cert_dirs=$(sudo find /etc/letsencrypt/live -maxdepth 1 -type d -name "*.* " 2>/dev/null | head -10)
    
    if [ -z "$cert_dirs" ]; then
        print_error "No SSL certificates found"
        echo ""
        echo -e "${YELLOW}Press Enter to return...${RESET}"
        read -r
        return
    fi
    
    echo -e "${GREEN}Found SSL certificates:${RESET}"
    echo "$cert_dirs" | while read -r cert_dir; do
        local domain=$(basename "$cert_dir")
        echo -e "  ${WHITE}• $domain${RESET}"
    done
    
    echo ""
    echo -e "${CYAN}📅 Setting up auto-renewal cron job...${RESET}"
    
    # Create renewal script
    local renewal_script="/usr/local/bin/trusttunnel-ssl-renewal.sh"
    cat <<'EOF' | sudo tee "$renewal_script" > /dev/null
#!/bin/bash
# TrustTunnel SSL Certificate Auto-Renewal Script

LOG_FILE="/var/log/trusttunnel-ssl-renewal.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "Starting SSL certificate renewal check..."

# Renew certificates
if certbot renew --quiet; then
    log_message "Certificate renewal check completed successfully"
    
    # Restart TrustTunnel services if certificates were renewed
    if systemctl is-active --quiet trusttunnel.service; then
        systemctl restart trusttunnel.service
        log_message "Restarted trusttunnel.service"
    fi
    
    # Restart client services
    for service in $(systemctl list-units --type=service --state=active | grep 'trusttunnel-' | awk '{print $1}'); do
        systemctl restart "$service"
        log_message "Restarted $service"
    done
    
else
    log_message "Certificate renewal failed"
fi

log_message "SSL renewal process completed"
EOF
    
    sudo chmod +x "$renewal_script"
    
    # Add cron job (runs twice daily)
    local cron_job="0 */12 * * * $renewal_script"
    (crontab -l 2>/dev/null | grep -v "$renewal_script"; echo "$cron_job") | crontab -
    
    print_success "SSL auto-renewal configured successfully"
    echo -e "${WHITE}• Renewal script: $renewal_script${RESET}"
    echo -e "${WHITE}• Runs twice daily at 00:00 and 12:00${RESET}"
    echo -e "${WHITE}• Log file: /var/log/trusttunnel-ssl-renewal.log${RESET}"
    
    echo ""
    echo -e "${YELLOW}Press Enter to return...${RESET}"
    read -r
}

# Function to setup service monitoring
setup_service_monitoring() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        📊 Service Monitoring Setup${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    echo -e "${CYAN}🔧 Setting up service monitoring...${RESET}"
    
    # Create monitoring script
    local monitor_script="/usr/local/bin/trusttunnel-monitor.sh"
    cat <<'EOF' | sudo tee "$monitor_script" > /dev/null
#!/bin/bash
# TrustTunnel Service Monitoring Script

LOG_FILE="/var/log/trusttunnel-monitor.log"
ALERT_EMAIL=""

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_service() {
    local service_name="$1"
    if systemctl is-active --quiet "$service_name"; then
        log_message "✅ $service_name is running"
        return 0
    else
        log_message "❌ $service_name is not running - attempting restart"
        if systemctl restart "$service_name"; then
            log_message "✅ Successfully restarted $service_name"
            return 0
        else
            log_message "❌ Failed to restart $service_name"
            return 1
        fi
    fi
}

log_message "Starting service monitoring check..."

# Check server service
if systemctl list-unit-files | grep -q "trusttunnel.service"; then
    check_service "trusttunnel.service"
fi

# Check client services
for service in $(systemctl list-units --type=service --all | grep 'trusttunnel-' | awk '{print $1}'); do
    check_service "$service"
done

log_message "Service monitoring check completed"
EOF
    
    sudo chmod +x "$monitor_script"
    
    # Setup systemd timer
    local timer_file="/etc/systemd/system/trusttunnel-monitor.timer"
    cat <<EOF | sudo tee "$timer_file" > /dev/null
[Unit]
Description=TrustTunnel Service Monitor Timer
Requires=trusttunnel-monitor.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Setup systemd service
    local service_file="/etc/systemd/system/trusttunnel-monitor.service"
    cat <<EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=TrustTunnel Service Monitor
After=network.target

[Service]
Type=oneshot
ExecStart=$monitor_script
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable trusttunnel-monitor.timer
    sudo systemctl start trusttunnel-monitor.timer
    
    print_success "Service monitoring configured successfully"
    echo -e "${WHITE}• Monitor script: $monitor_script${RESET}"
    echo -e "${WHITE}• Runs every 5 minutes${RESET}"
    echo -e "${WHITE}• Log file: /var/log/trusttunnel-monitor.log${RESET}"
    echo -e "${WHITE}• Auto-restart failed services${RESET}"
    
    echo ""
    echo -e "${YELLOW}Press Enter to return...${RESET}"
    read -r
}

# Function to setup backup system
setup_backup_system() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        💾 Backup System Setup${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    echo -e "${WHITE}Enter backup directory path (default: /opt/trusttunnel-backups):${RESET} "
    read -r backup_dir
    backup_dir=${backup_dir:-/opt/trusttunnel-backups}
    
    echo -e "${CYAN}📁 Creating backup directory...${RESET}"
    sudo mkdir -p "$backup_dir"
    
    # Create backup script
    local backup_script="/usr/local/bin/trusttunnel-backup.sh"
    cat <<EOF | sudo tee "$backup_script" > /dev/null
#!/bin/bash
# TrustTunnel Backup Script

BACKUP_DIR="$backup_dir"
LOG_FILE="/var/log/trusttunnel-backup.log"
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="trusttunnel_backup_\$DATE"

log_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$LOG_FILE"
}

log_message "Starting backup process..."

# Create backup directory
mkdir -p "\$BACKUP_DIR/\$BACKUP_NAME"

# Backup service files
log_message "Backing up service files..."
sudo cp -r /etc/systemd/system/trusttunnel*.service "\$BACKUP_DIR/\$BACKUP_NAME/" 2>/dev/null || true

# Backup rstun binaries
if [ -d "rstun" ]; then
    log_message "Backing up rstun binaries..."
    cp -r rstun "\$BACKUP_DIR/\$BACKUP_NAME/"
fi

# Backup SSL certificates
log_message "Backing up SSL certificates..."
sudo cp -r /etc/letsencrypt "\$BACKUP_DIR/\$BACKUP_NAME/" 2>/dev/null || true

# Backup configuration
log_message "Backing up configuration..."
echo "# TrustTunnel Backup Information" > "\$BACKUP_DIR/\$BACKUP_NAME/backup_info.txt"
echo "Date: \$(date)" >> "\$BACKUP_DIR/\$BACKUP_NAME/backup_info.txt"
echo "Hostname: \$(hostname)" >> "\$BACKUP_DIR/\$BACKUP_NAME/backup_info.txt"
systemctl list-units --type=service | grep trusttunnel >> "\$BACKUP_DIR/\$BACKUP_NAME/backup_info.txt"

# Create archive
cd "\$BACKUP_DIR"
tar -czf "\$BACKUP_NAME.tar.gz" "\$BACKUP_NAME"
rm -rf "\$BACKUP_NAME"

# Keep only last 7 backups
ls -t \$BACKUP_DIR/trusttunnel_backup_*.tar.gz | tail -n +8 | xargs -r rm

log_message "Backup completed: \$BACKUP_NAME.tar.gz"
EOF
    
    sudo chmod +x "$backup_script"
    
    # Setup cron job for daily backup
    local cron_job="0 2 * * * $backup_script"
    (crontab -l 2>/dev/null | grep -v "$backup_script"; echo "$cron_job") | crontab -
    
    print_success "Backup system configured successfully"
    echo -e "${WHITE}• Backup directory: $backup_dir${RESET}"
    echo -e "${WHITE}• Backup script: $backup_script${RESET}"
    echo -e "${WHITE}• Runs daily at 2:00 AM${RESET}"
    echo -e "${WHITE}• Keeps last 7 backups${RESET}"
    echo -e "${WHITE}• Log file: /var/log/trusttunnel-backup.log${RESET}"
    
    echo ""
    echo -e "${YELLOW}Press Enter to return...${RESET}"
    read -r
}

# Function to view system logs
view_system_logs() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        📋 System Logs Viewer${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    echo -e "${WHITE}Select log type:${RESET}"
    echo -e "  ${YELLOW}1)${RESET} SSL Renewal Logs"
    echo -e "  ${YELLOW}2)${RESET} Service Monitor Logs"
    echo -e "  ${YELLOW}3)${RESET} Backup Logs"
    echo -e "  ${YELLOW}4)${RESET} System Journal (TrustTunnel)"
    echo -e "  ${YELLOW}5)${RESET} Return"
    echo ""
    echo -e "${WHITE}Your choice:${RESET} "
    read -r log_choice
    
    case $log_choice in
        1)
            if [ -f "/var/log/trusttunnel-ssl-renewal.log" ]; then
                echo -e "${CYAN}📋 SSL Renewal Logs:${RESET}"
                tail -50 /var/log/trusttunnel-ssl-renewal.log
            else
                print_warning "SSL renewal log not found"
            fi
            ;;
        2)
            if [ -f "/var/log/trusttunnel-monitor.log" ]; then
                echo -e "${CYAN}📋 Service Monitor Logs:${RESET}"
                tail -50 /var/log/trusttunnel-monitor.log
            else
                print_warning "Monitor log not found"
            fi
            ;;
        3)
            if [ -f "/var/log/trusttunnel-backup.log" ]; then
                echo -e "${CYAN}📋 Backup Logs:${RESET}"
                tail -50 /var/log/trusttunnel-backup.log
            else
                print_warning "Backup log not found"
            fi
            ;;
        4)
            echo -e "${CYAN}📋 System Journal (TrustTunnel Services):${RESET}"
            sudo journalctl -u "trusttunnel*" -n 50 --no-pager
            ;;
        5)
            return
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac
    
    echo ""
    echo -e "${YELLOW}Press Enter to return...${RESET}"
    read -r
}

# Function to show advanced management menu
advanced_management_menu() {
    while true; do
        clear
        echo ""
        draw_line "$MAGENTA" "=" 40
        echo -e "${MAGENTA}        ⚙️ Advanced Management${RESET}"
        draw_line "$MAGENTA" "=" 40
        echo ""
        echo -e "  ${YELLOW}1)${RESET} ${WHITE}SSL Auto-Renewal Setup${RESET}"
        echo -e "  ${YELLOW}2)${RESET} ${WHITE}Service Monitoring Setup${RESET}"
        echo -e "  ${YELLOW}3)${RESET} ${WHITE}Backup System Setup${RESET}"
        echo -e "  ${YELLOW}4)${RESET} ${WHITE}View System Logs${RESET}"
        echo -e "  ${YELLOW}5)${RESET} ${WHITE}Performance Monitoring${RESET}"
        echo -e "  ${YELLOW}6)${RESET} ${WHITE}Security Hardening${RESET}"
        echo -e "  ${YELLOW}7)${RESET} ${WHITE}Return to main menu${RESET}"
        echo ""
        draw_line "$MAGENTA" "-" 40
        echo -e "${WHITE}Your choice:${RESET} "
        read -r adv_choice
        echo ""
        
        case $adv_choice in
            1)
                setup_ssl_renewal
                ;;
            2)
                setup_service_monitoring
                ;;
            3)
                setup_backup_system
                ;;
            4)
                view_system_logs
                ;;
            5)
                show_performance_monitoring
                ;;
            6)
                security_hardening_menu
                ;;
            7)
                break
                ;;
            *)
                print_error "Invalid option"
                echo ""
                echo -e "${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
        esac
    done
}

# Function to show performance monitoring
show_performance_monitoring() {
    clear
    echo ""
    draw_line "$CYAN" "=" 40
    echo -e "${CYAN}        📈 Performance Monitoring${RESET}"
    draw_line "$CYAN" "=" 40
    echo ""
    
    echo -e "${CYAN}🖥️ System Resources:${RESET}"
    echo -e "${WHITE}CPU Usage:${RESET}"
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//'
    
    echo -e "${WHITE}Memory Usage:${RESET}"
    free -h | grep "Mem:"
    
    echo -e "${WHITE}Disk Usage:${RESET}"
    df -h | grep -E "/$|/opt|/var"
    
    echo ""
    echo -e "${CYAN}🌐 Network Connections:${RESET}"
    netstat -tuln | grep -E ":6060|:8800|:8801|:8802|:8803|:8804|:8805" | head -10
    
    echo ""
    echo -e "${CYAN}📊 Service Resource Usage:${RESET}"
    
    # Check TrustTunnel processes
    local trusttunnel_pids=$(pgrep -f "rstun" 2>/dev/null || echo "")
    if [ -n "$trusttunnel_pids" ]; then
        echo -e "${WHITE}TrustTunnel Processes:${RESET}"
        ps -p $trusttunnel_pids -o pid,ppid,cmd,%mem,%cpu --no-headers 2>/dev/null || echo "No processes found"
    else
        echo -e "${YELLOW}No TrustTunnel processes running${RESET}"
    fi
    
    echo ""
    echo -e "${YELLOW}Press Enter to return...${RESET}"
    read -r
}

# Function to show security hardening menu
security_hardening_menu() {
    clear
    echo ""
    draw_line "$RED" "=" 40
    echo -e "${RED}        🔒 Security Hardening${RESET}"
    draw_line "$RED" "=" 40
    echo ""
    
    echo -e "${CYAN}🔍 Security Status Check:${RESET}"
    
    # Check firewall status
    local firewall_type=$(detect_firewall)
    if [ "$firewall_type" != "none" ]; then
        echo -e "${GREEN}✅ Firewall: $firewall_type active${RESET}"
    else
        echo -e "${RED}❌ Firewall: Not detected${RESET}"
    fi
    
    # Check SSL certificates
    local ssl_certs=$(sudo find /etc/letsencrypt/live -name "*.pem" 2>/dev/null | wc -l)
    if [ "$ssl_certs" -gt 0 ]; then
        echo -e "${GREEN}✅ SSL Certificates: $ssl_certs found${RESET}"
    else
        echo -e "${YELLOW}⚠️ SSL Certificates: None found${RESET}"
    fi
    
    # Check service permissions
    local service_files=$(find /etc/systemd/system -name "trusttunnel*.service" 2>/dev/null)
    if [ -n "$service_files" ]; then
        echo -e "${GREEN}✅ Service Files: Properly configured${RESET}"
    else
        echo -e "${YELLOW}⚠️ Service Files: None found${RESET}"
    fi
    
    # Check for fail2ban
    if command_exists fail2ban-server; then
        echo -e "${GREEN}✅ Fail2ban: Installed${RESET}"
    else
        echo -e "${YELLOW}⚠️ Fail2ban: Not installed${RESET}"
    fi
    
    echo ""
    echo -e "${WHITE}Security Recommendations:${RESET}"
    echo -e "  ${CYAN}• Keep system updated${RESET}"
    echo -e "  ${CYAN}• Use strong passwords${RESET}"
    echo -e "  ${CYAN}• Monitor logs regularly${RESET}"
    echo -e "  ${CYAN}• Limit SSH access${RESET}"
    echo -e "  ${CYAN}• Use fail2ban for intrusion prevention${RESET}"
    
    echo ""
    echo -e "${YELLOW}Press Enter to return...${RESET}"
    read -r
}

# Run main function
main "$@"
