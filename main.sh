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
    fi
    
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
                    # Try to extract ports from service file before deletion
                    if [ -f "$service_file" ]; then
                        # Extract mapping arguments from service file
                        local tcp_mappings=$(grep -o '\--tcp-mappings "[^"]*"' "$service_file" | sed 's/--tcp-mappings "//;s/"//')
                        local udp_mappings=$(grep -o '\--udp-mappings "[^"]*"' "$service_file" | sed 's/--udp-mappings "//;s/"//')
                        
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
        echo -e "  ${YELLOW}3)${RESET} ${WHITE}Delete service${RESET}"
        echo -e "  ${YELLOW}4)${RESET} ${WHITE}Back to main menu${RESET}"
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
            4)
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
        echo -e "  ${YELLOW}3)${RESET} ${WHITE}Delete a client${RESET}"
        echo -e "  ${YELLOW}4)${RESET} ${WHITE}Back to main menu${RESET}"
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
                delete_client_menu
                ;;
            4)
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
        echo -e "${RED}3) Uninstall TrustTunnel${RESET}"
        echo -e "${WHITE}4) Exit${RESET}"
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
                uninstall_trusttunnel_action
                ;;
            4)
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

# Run main function
main "$@"
