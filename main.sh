#!/bin/bash

# TrustTunnel Management Script - Optimized Version
# Developed by ErfanXRay => https://github.com/Erfan-XRay/TrustTunnel
# Telegram Channel => @Erfan_XRay

# Define colors for better terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD_GREEN='\033[1;32m'
BOLD_RED='\033[1;31m'
BOLD_YELLOW='\033[1;33m'
RESET='\033[0m'

# Global variables
RUST_IS_READY=false
CARGO_ENV_FILE="$HOME/.cargo/env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/trusttunnel-manager.log"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

# Function to draw a colored line
draw_line() {
    local color="$1"
    local char="$2"
    local length=${3:-50}
    printf "${color}"
    for ((i=0; i<length; i++)); do
        printf "$char"
    done
    printf "${RESET}\n"
}

# Function to print messages with different levels
print_success() {
    local message="$1"
    echo -e "${GREEN}✅ $message${RESET}"
    log_message "SUCCESS" "$message"
}

print_error() {
    local message="$1"
    echo -e "${RED}❌ $message${RESET}"
    log_message "ERROR" "$message"
}

print_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠️ $message${RESET}"
    log_message "WARNING" "$message"
}

print_info() {
    local message="$1"
    echo -e "${CYAN}ℹ️ $message${RESET}"
    log_message "INFO" "$message"
}

# Function to show loading animation
show_loading() {
    local pid=$1
    local message="$2"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r${CYAN}${spin:$i:1} $message...${RESET}"
        sleep 0.1
    done
    printf "\r"
}

# Function to confirm action
confirm_action() {
    local message="$1"
    local default="${2:-N}"
    
    if [[ "$default" == "Y" ]]; then
        echo -e "${YELLOW}$message (Y/n):${RESET} "
    else
        echo -e "${YELLOW}$message (y/N):${RESET} "
    fi
    
    read -r response
    
    if [[ "$default" == "Y" ]]; then
        [[ ! "$response" =~ ^[Nn]$ ]]
    else
        [[ "$response" =~ ^[Yy]$ ]]
    fi
}

# Function to pause and wait for user input
pause() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${RESET}"
    read -r
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate inputs
validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

# ============================================================================
# SYSTEM FUNCTIONS
# ============================================================================

# Function to install system dependencies
install_dependencies() {
    print_info "Installing system dependencies"
    
    if ! sudo apt update &>/dev/null; then
        print_error "Failed to update package list"
        return 1
    fi
    
    local packages=(
        "build-essential" "curl" "pkg-config" "libssl-dev" 
        "git" "figlet" "certbot" "wget" "tar" "net-tools"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            print_info "Installing $package"
            sudo apt install -y "$package" &>/dev/null || {
                print_error "Failed to install $package"
                return 1
            }
        fi
    done
    
    print_success "All dependencies installed successfully"
    return 0
}

# Function to install Rust
install_rust() {
    print_info "Checking Rust installation"
    
    if command_exists rustc && command_exists cargo; then
        print_success "Rust is already installed: $(rustc --version)"
        RUST_IS_READY=true
        return 0
    fi
    
    print_info "Installing Rust"
    
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y &>/dev/null; then
        print_success "Rust installed successfully"
        
        if [ -f "$CARGO_ENV_FILE" ]; then
            source "$CARGO_ENV_FILE"
        else
            export PATH="$HOME/.cargo/bin:$PATH"
        fi
        
        if command_exists rustc && command_exists cargo; then
            print_success "Rust version: $(rustc --version)"
            RUST_IS_READY=true
            return 0
        fi
    fi
    
    print_error "Rust installation failed"
    return 1
}

# ============================================================================
# FIREWALL FUNCTIONS
# ============================================================================

# Function to detect firewall type
detect_firewall() {
    if command_exists ufw && sudo ufw status | grep -q "Status: active"; then
        echo "ufw"
    elif command_exists iptables; then
        echo "iptables"
    else
        echo "none"
    fi
}

# Function to manage firewall ports
manage_firewall_port() {
    local action="$1"  # open or close
    local port="$2"
    local protocol="$3"  # tcp, udp, or both
    local firewall_type=$(detect_firewall)
    
    case "$firewall_type" in
        "ufw")
            case "$action" in
                "open")
                    case "$protocol" in
                        "tcp") sudo ufw allow "$port/tcp" &>/dev/null ;;
                        "udp") sudo ufw allow "$port/udp" &>/dev/null ;;
                        "both") 
                            sudo ufw allow "$port/tcp" &>/dev/null
                            sudo ufw allow "$port/udp" &>/dev/null
                            ;;
                    esac
                    # Also add to iptables as backup
                    case "$protocol" in
                        "tcp") sudo iptables -I INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null ;;
                        "udp") sudo iptables -I INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null ;;
                        "both")
                            sudo iptables -I INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null
                            sudo iptables -I INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null
                            ;;
                    esac
                    ;;
                "close")
                    case "$protocol" in
                        "tcp") 
                            sudo ufw delete allow "$port/tcp" &>/dev/null
                            sudo iptables -D INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null
                            ;;
                        "udp") 
                            sudo ufw delete allow "$port/udp" &>/dev/null
                            sudo iptables -D INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null
                            ;;
                        "both")
                            sudo ufw delete allow "$port/tcp" &>/dev/null
                            sudo ufw delete allow "$port/udp" &>/dev/null
                            sudo iptables -D INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null
                            sudo iptables -D INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null
                            ;;
                    esac
                    ;;
            esac
            ;;
        "iptables")
            case "$action" in
                "open")
                    case "$protocol" in
                        "tcp") sudo iptables -I INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null ;;
                        "udp") sudo iptables -I INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null ;;
                        "both")
                            sudo iptables -I INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null
                            sudo iptables -I INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null
                            ;;
                    esac
                    ;;
                "close")
                    case "$protocol" in
                        "tcp") sudo iptables -D INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null ;;
                        "udp") sudo iptables -D INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null ;;
                        "both")
                            sudo iptables -D INPUT -p tcp --dport "$port" -j ACCEPT &>/dev/null
                            sudo iptables -D INPUT -p udp --dport "$port" -j ACCEPT &>/dev/null
                            ;;
                    esac
                    ;;
            esac
            # Save iptables rules
            if command_exists iptables-save && command_exists netfilter-persistent; then
                sudo netfilter-persistent save &>/dev/null
            elif [ -f /etc/iptables/rules.v4 ]; then
                sudo iptables-save | sudo tee /etc/iptables/rules.v4 &>/dev/null
            fi
            ;;
    esac
}

# Function to check port status
check_port_status() {
    local port="$1"
    local protocol="$2"
    local firewall_type=$(detect_firewall)
    
    case "$firewall_type" in
        "ufw")
            local ufw_status=$(sudo ufw status 2>/dev/null)
            if echo "$ufw_status" | grep -q "$port/$protocol\|$port "; then
                echo "open_ufw"
            elif sudo iptables -L INPUT -n | grep -q "dpt:$port.*$protocol"; then
                echo "open_iptables"
            else
                echo "closed"
            fi
            ;;
        "iptables")
            if sudo iptables -L INPUT -n | grep -q "dpt:$port"; then
                echo "open"
            else
                echo "closed"
            fi
            ;;
        *)
            echo "no_firewall"
            ;;
    esac
}

# ============================================================================
# SERVICE MANAGEMENT FUNCTIONS
# ============================================================================

# Function to get all TrustTunnel services
get_trusttunnel_services() {
    local service_type="$1"  # server, client, or all
    
    case "$service_type" in
        "server")
            if [ -f "/etc/systemd/system/trusttunnel.service" ]; then
                echo "trusttunnel.service"
            fi
            ;;
        "client")
            systemctl list-units --type=service --all | grep 'trusttunnel-' | awk '{print $1}' | sed 's/.service$//'
            ;;
        "all")
            {
                if [ -f "/etc/systemd/system/trusttunnel.service" ]; then
                    echo "trusttunnel.service"
                fi
                systemctl list-units --type=service --all | grep 'trusttunnel-' | awk '{print $1}' | sed 's/.service$//'
            }
            ;;
    esac
}

# Function to get service status
get_service_status() {
    local service="$1"
    
    if systemctl is-active --quiet "$service"; then
        if systemctl is-enabled --quiet "$service"; then
            echo "active_enabled"
        else
            echo "active_disabled"
        fi
    else
        if systemctl is-enabled --quiet "$service"; then
            echo "inactive_enabled"
        else
            echo "inactive_disabled"
        fi
    fi
}

# Function to control service
control_service() {
    local action="$1"  # start, stop, restart, enable, disable
    local service="$2"
    
    case "$action" in
        "start")
            sudo systemctl start "$service" &>/dev/null
            ;;
        "stop")
            sudo systemctl stop "$service" &>/dev/null
            ;;
        "restart")
            sudo systemctl restart "$service" &>/dev/null
            ;;
        "enable")
            sudo systemctl enable "$service" &>/dev/null
            ;;
        "disable")
            sudo systemctl disable "$service" &>/dev/null
            ;;
    esac
}

# Function to show service logs
show_service_logs() {
    local service="$1"
    local lines="${2:-50}"
    
    clear
    draw_line "$BLUE" "=" 60
    echo -e "${BLUE}        📋 Service Logs: $service${RESET}"
    draw_line "$BLUE" "=" 60
    echo ""
    
    local status=$(get_service_status "$service")
    case "$status" in
        "active_enabled") echo -e "${GREEN}🟢 Status: Active & Enabled${RESET}" ;;
        "active_disabled") echo -e "${YELLOW}🟡 Status: Active but Disabled${RESET}" ;;
        "inactive_enabled") echo -e "${YELLOW}🟡 Status: Inactive but Enabled${RESET}" ;;
        "inactive_disabled") echo -e "${RED}🔴 Status: Inactive & Disabled${RESET}" ;;
    esac
    
    echo ""
    sudo journalctl -u "$service" -n "$lines" --no-pager
    echo ""
    pause
}

# ============================================================================
# INSTALLATION FUNCTIONS
# ============================================================================

# Function to install TrustTunnel
install_trusttunnel() {
    clear
    draw_line "$CYAN" "=" 50
    echo -e "${CYAN}        📥 Installing TrustTunnel${RESET}"
    draw_line "$CYAN" "=" 50
    echo ""
    
    # Remove existing installation
    if [ -d "rstun" ]; then
        print_info "Removing existing installation"
        rm -rf rstun
    fi
    
    # Detect architecture
    local arch=$(uname -m)
    local filename=""
    
    case "$arch" in
        "x86_64") filename="rstun-linux-x86_64.tar.gz" ;;
        "aarch64"|"arm64") filename="rstun-linux-aarch64.tar.gz" ;;
        "armv7l") filename="rstun-linux-armv7.tar.gz" ;;
        *)
            print_error "Unsupported architecture: $arch"
            if confirm_action "Try x86_64 version as fallback?"; then
                filename="rstun-linux-x86_64.tar.gz"
            else
                pause
                return 1
            fi
            ;;
    esac
    
    local download_url="https://github.com/neevek/rstun/releases/download/release%2F0.7.1/${filename}"
    
    # Download
    print_info "Downloading $filename"
    if wget -q --show-progress "$download_url" -O "$filename"; then
        print_success "Download completed"
    else
        print_error "Download failed"
        pause
        return 1
    fi
    
    # Extract
    print_info "Extracting files"
    if tar -xzf "$filename"; then
        mv "${filename%.tar.gz}" rstun 2>/dev/null || true
        print_success "Extraction completed"
    else
        print_error "Extraction failed"
        rm -f "$filename"
        pause
        return 1
    fi
    
    # Set permissions
    find rstun -type f -exec chmod +x {} \; 2>/dev/null || true
    rm -f "$filename"
    
    print_success "TrustTunnel installed successfully!"
    pause
}

# Function to uninstall TrustTunnel
uninstall_trusttunnel() {
    clear
    draw_line "$RED" "=" 50
    echo -e "${RED}        🗑️ Uninstall TrustTunnel${RESET}"
    draw_line "$RED" "=" 50
    echo ""
    
    if ! confirm_action "⚠️ This will remove ALL TrustTunnel services and files. Continue?"; then
        return
    fi
    
    # Stop and remove all services
    print_info "Removing TrustTunnel services"
    mapfile -t services < <(get_trusttunnel_services "all")
    
    for service in "${services[@]}"; do
        if [ -n "$service" ]; then
            print_info "Removing $service"
            control_service "stop" "$service"
            control_service "disable" "$service"
            sudo rm -f "/etc/systemd/system/${service}.service"
        fi
    done
    
    sudo systemctl daemon-reload
    
    # Remove firewall rules
    if confirm_action "Close TrustTunnel ports in firewall?"; then
        local common_ports=("6060" "8800" "8801" "8802" "8803" "8804" "8805")
        for port in "${common_ports[@]}"; do
            manage_firewall_port "close" "$port" "both"
        done
        print_success "Firewall rules removed"
    fi
    
    # Remove files
    if [ -d "rstun" ]; then
        rm -rf rstun
        print_success "Installation files removed"
    fi
    
    print_success "TrustTunnel uninstalled successfully"
    pause
}

# ============================================================================
# SERVER MANAGEMENT FUNCTIONS
# ============================================================================

# Function to add new server
add_server() {
    clear
    draw_line "$CYAN" "=" 50
    echo -e "${CYAN}        ➕ Add TrustTunnel Server${RESET}"
    draw_line "$CYAN" "=" 50
    echo ""
    
    # Check installation
    if [ ! -f "rstun/rstund" ]; then
        print_error "TrustTunnel server binary not found"
        print_info "Please install TrustTunnel first"
        pause
        return 1
    fi
    
    # Get domain
    local domain
    while true; do
        echo -e "${WHITE}Enter your domain (e.g., server.example.com):${RESET} "
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
    
    # Get email
    local email
    while true; do
        echo -e "${WHITE}Enter email for SSL certificate:${RESET} "
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
    
    # Get ports
    local listen_port tcp_port udp_port password
    
    echo -e "${WHITE}Enter listen port (default: 6060):${RESET} "
    read -r listen_port
    listen_port=${listen_port:-6060}
    
    echo -e "${WHITE}Enter TCP upstream port (default: 8800):${RESET} "
    read -r tcp_port
    tcp_port=${tcp_port:-8800}
    
    echo -e "${WHITE}Enter UDP upstream port (default: 8800):${RESET} "
    read -r udp_port
    udp_port=${udp_port:-8800}
    
    echo -e "${WHITE}Enter password:${RESET} "
    read -r password
    
    # Validate inputs
    if ! validate_port "$listen_port" || ! validate_port "$tcp_port" || ! validate_port "$udp_port"; then
        print_error "Invalid port numbers"
        pause
        return 1
    fi
    
    if [ -z "$password" ]; then
        print_error "Password cannot be empty"
        pause
        return 1
    fi
    
    # SSL Certificate
    local cert_path="/etc/letsencrypt/live/$domain"
    if [ ! -d "$cert_path" ]; then
        print_info "Requesting SSL certificate"
        if ! sudo certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m "$email"; then
            print_error "Failed to obtain SSL certificate"
            pause
            return 1
        fi
    fi
    
    # Configure firewall
    if confirm_action "Configure firewall automatically?" "Y"; then
        manage_firewall_port "open" "$listen_port" "tcp"
        [ "$tcp_port" != "$listen_port" ] && manage_firewall_port "open" "$tcp_port" "tcp"
        [ "$udp_port" != "$listen_port" ] && [ "$udp_port" != "$tcp_port" ] && manage_firewall_port "open" "$udp_port" "udp"
        print_success "Firewall configured"
    fi
    
    # Remove existing server service
    if [ -f "/etc/systemd/system/trusttunnel.service" ]; then
        control_service "stop" "trusttunnel.service"
        control_service "disable" "trusttunnel.service"
        sudo rm -f "/etc/systemd/system/trusttunnel.service"
    fi
    
    # Create service file
    cat <<EOF | sudo tee "/etc/systemd/system/trusttunnel.service" > /dev/null
[Unit]
Description=TrustTunnel Server Service
After=network.target

[Service]
Type=simple
ExecStart=$(pwd)/rstun/rstund --addr 0.0.0.0:$listen_port --tcp-upstream $tcp_port --udp-upstream $udp_port --password "$password" --cert "$cert_path/fullchain.pem" --key "$cert_path/privkey.pem"
Restart=always
RestartSec=5
User=$(whoami)
WorkingDirectory=$(pwd)

[Install]
WantedBy=multi-user.target
EOF
    
    # Start service
    sudo systemctl daemon-reload
    if control_service "enable" "trusttunnel.service" && control_service "start" "trusttunnel.service"; then
        print_success "TrustTunnel server started successfully!"
        
        if confirm_action "View service logs?"; then
            show_service_logs "trusttunnel.service"
        fi
    else
        print_error "Failed to start TrustTunnel server"
    fi
    
    pause
}

# ============================================================================
# CLIENT MANAGEMENT FUNCTIONS
# ============================================================================

# Function to add new client
add_client() {
    clear
    draw_line "$CYAN" "=" 50
    echo -e "${CYAN}        ➕ Add TrustTunnel Client${RESET}"
    draw_line "$CYAN" "=" 50
    echo ""
    
    # Check installation
    if [ ! -f "rstun/rstunc" ]; then
        print_error "TrustTunnel client binary not found"
        print_info "Please install TrustTunnel first"
        pause
        return 1
    fi
    
    # Get client name
    local client_name
    while true; do
        echo -e "${WHITE}Enter client name (e.g., server1, iran1):${RESET} "
        read -r client_name
        
        if [ -z "$client_name" ]; then
            print_error "Client name cannot be empty"
            continue
        fi
        
        if [ -f "/etc/systemd/system/trusttunnel-${client_name}.service" ]; then
            print_error "Client with this name already exists"
            continue
        fi
        
        break
    done
    
    # Get server details
    local server_addr
    while true; do
        echo -e "${WHITE}Enter server address:port (e.g., server.domain.com:6060):${RESET} "
        read -r server_addr
        
        if [ -z "$server_addr" ]; then
            print_error "Server address cannot be empty"
            continue
        fi
        
        if [[ "$server_addr" =~ ^[^:]+:[0-9]+$ ]]; then
            break
        else
            print_error "Invalid format. Use: domain:port or ip:port"
        fi
    done
    
    # Get tunnel mode
    local tunnel_mode
    echo ""
    echo -e "${WHITE}Select tunnel mode:${RESET}"
    echo -e "  ${YELLOW}1)${RESET} TCP only"
    echo -e "  ${YELLOW}2)${RESET} UDP only"
    echo -e "  ${YELLOW}3)${RESET} Both TCP and UDP"
    echo -e "${WHITE}Your choice (1-3):${RESET} "
    read -r mode_choice
    
    case "$mode_choice" in
        1) tunnel_mode="tcp" ;;
        2) tunnel_mode="udp" ;;
        3) tunnel_mode="both" ;;
        *) print_error "Invalid choice"; pause; return 1 ;;
    esac
    
    # Get password
    local password
    echo -e "${WHITE}Enter password:${RESET} "
    read -r password
    
    if [ -z "$password" ]; then
        print_error "Password cannot be empty"
        pause
        return 1
    fi
    
    # Get port mappings
    local port_count
    echo -e "${WHITE}How many ports to tunnel?${RESET} "
    read -r port_count
    
    if ! [[ "$port_count" =~ ^[0-9]+$ ]] || [ "$port_count" -lt 1 ] || [ "$port_count" -gt 50 ]; then
        print_error "Invalid number. Enter 1-50"
        pause
        return 1
    fi
    
    local mappings=""
    for ((i=1; i<=port_count; i++)); do
        local port
        echo -e "${WHITE}Port #$i:${RESET} "
        read -r port
        
        if ! validate_port "$port"; then
            print_error "Invalid port: $port"
            pause
            return 1
        fi
        
        local mapping="IN^0.0.0.0:$port^0.0.0.0:$port"
        if [ -z "$mappings" ]; then
            mappings="$mapping"
        else
            mappings="$mappings,$mapping"
        fi
    done
    
    # Configure firewall
    if confirm_action "Configure firewall automatically?" "Y"; then
        IFS=',' read -ra MAPPING_ARRAY <<< "$mappings"
        for mapping in "${MAPPING_ARRAY[@]}"; do
            local port=$(echo "$mapping" | cut -d'^' -f2 | cut -d':' -f2)
            manage_firewall_port "open" "$port" "$tunnel_mode"
        done
        print_success "Firewall configured"
    fi
    
    # Create service
    local service_name="trusttunnel-$client_name"
    local mapping_args=""
    
    case "$tunnel_mode" in
        "tcp") mapping_args="--tcp-mappings \"$mappings\"" ;;
        "udp") mapping_args="--udp-mappings \"$mappings\"" ;;
        "both") mapping_args="--tcp-mappings \"$mappings\" --udp-mappings \"$mappings\"" ;;
    esac
    
    cat <<EOF | sudo tee "/etc/systemd/system/${service_name}.service" > /dev/null
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
    
    # Start service
    sudo systemctl daemon-reload
    if control_service "enable" "$service_name" && control_service "start" "$service_name"; then
        print_success "Client '$client_name' started successfully!"
        
        if confirm_action "View service logs?"; then
            show_service_logs "$service_name"
        fi
    else
        print_error "Failed to start client"
    fi
    
    pause
}

# ============================================================================
# MONITORING FUNCTIONS
# ============================================================================

# Function to show service overview
show_service_overview() {
    clear
    draw_line "$CYAN" "=" 60
    echo -e "${CYAN}        📊 TrustTunnel Services Overview${RESET}"
    draw_line "$CYAN" "=" 60
    echo ""
    
    # Server status
    echo -e "${BOLD_YELLOW}🖥️  SERVER STATUS${RESET}"
    draw_line "$YELLOW" "-" 30
    
    if [ -f "/etc/systemd/system/trusttunnel.service" ]; then
        local status=$(get_service_status "trusttunnel.service")
        case "$status" in
            "active_enabled") echo -e "${GREEN}🟢 trusttunnel.service: Running & Auto-start${RESET}" ;;
            "active_disabled") echo -e "${YELLOW}🟡 trusttunnel.service: Running (Manual start)${RESET}" ;;
            "inactive_enabled") echo -e "${YELLOW}🟡 trusttunnel.service: Stopped (Auto-start enabled)${RESET}" ;;
            "inactive_disabled") echo -e "${RED}🔴 trusttunnel.service: Stopped${RESET}" ;;
        esac
    else
        echo -e "${YELLOW}🟡 No server configured${RESET}"
    fi
    
    echo ""
    
    # Client status
    echo -e "${BOLD_YELLOW}💻 CLIENT STATUS${RESET}"
    draw_line "$YELLOW" "-" 30
    
    mapfile -t clients < <(get_trusttunnel_services "client")
    
    if [ ${#clients[@]} -eq 0 ]; then
        echo -e "${YELLOW}🟡 No clients configured${RESET}"
    else
        for client in "${clients[@]}"; do
            if [ -n "$client" ]; then
                local status=$(get_service_status "$client")
                case "$status" in
                    "active_enabled") echo -e "${GREEN}🟢 $client: Running & Auto-start${RESET}" ;;
                    "active_disabled") echo -e "${YELLOW}🟡 $client: Running (Manual start)${RESET}" ;;
                    "inactive_enabled") echo -e "${YELLOW}🟡 $client: Stopped (Auto-start enabled)${RESET}" ;;
                    "inactive_disabled") echo -e "${RED}🔴 $client: Stopped${RESET}" ;;
                esac
            fi
        done
    fi
    
    echo ""
    
    # Summary
    echo -e "${BOLD_YELLOW}📈 SUMMARY${RESET}"
    draw_line "$YELLOW" "-" 30
    
    local total_services=0
    local active_services=0
    
    # Count server
    if [ -f "/etc/systemd/system/trusttunnel.service" ]; then
        ((total_services++))
        if systemctl is-active --quiet "trusttunnel.service"; then
            ((active_services++))
        fi
    fi
    
    # Count clients
    for client in "${clients[@]}"; do
        if [ -n "$client" ]; then
            ((total_services++))
            if systemctl is-active --quiet "$client"; then
                ((active_services++))
            fi
        fi
    done
    
    echo -e "${WHITE}Total Services: $total_services${RESET}"
    echo -e "${GREEN}Active Services: $active_services${RESET}"
    echo -e "${RED}Inactive Services: $((total_services - active_services))${RESET}"
    
    echo ""
    pause
}

# Function for quick service operations
quick_service_operations() {
    while true; do
        clear
        draw_line "$GREEN" "=" 50
        echo -e "${GREEN}        ⚡ Quick Service Operations${RESET}"
        draw_line "$GREEN" "=" 50
        echo ""
        
        echo -e "${WHITE}Select operation:${RESET}"
        echo -e "  ${YELLOW}1)${RESET} ${WHITE}Start all services${RESET}"
        echo -e "  ${YELLOW}2)${RESET} ${WHITE}Stop all services${RESET}"
        echo -e "  ${YELLOW}3)${RESET} ${WHITE}Restart all services${RESET}"
        echo -e "  ${YELLOW}4)${RESET} ${WHITE}Enable auto-start for all${RESET}"
        echo -e "  ${YELLOW}5)${RESET} ${WHITE}View all service logs${RESET}"
        echo -e "  ${YELLOW}6)${RESET} ${WHITE}Service health check${RESET}"
        echo -e "  ${YELLOW}7)${RESET} ${WHITE}Return to main menu${RESET}"
        echo ""
        echo -e "${WHITE}Your choice:${RESET} "
        read -r choice
        
        case $choice in
            1|2|3|4)
                local action
                case $choice in
                    1) action="start" ;;
                    2) action="stop" ;;
                    3) action="restart" ;;
                    4) action="enable" ;;
                esac
                
                print_info "Performing $action on all services"
                mapfile -t all_services < <(get_trusttunnel_services "all")
                
                for service in "${all_services[@]}"; do
                    if [ -n "$service" ]; then
                        print_info "${action^}ing $service"
                        control_service "$action" "$service"
                    fi
                done
                
                print_success "Operation completed"
                pause
                ;;
            5)
                mapfile -t all_services < <(get_trusttunnel_services "all")
                for service in "${all_services[@]}"; do
                    if [ -n "$service" ]; then
                        show_service_logs "$service" 20
                    fi
                done
                ;;
            6)
                service_health_check
                ;;
            7)
                break
                ;;
            *)
                print_error "Invalid choice"
                pause
                ;;
        esac
    done
}

# Function for service health check
service_health_check() {
    clear
    draw_line "$CYAN" "=" 50
    echo -e "${CYAN}        🏥 Service Health Check${RESET}"
    draw_line "$CYAN" "=" 50
    echo ""
    
    mapfile -t all_services < <(get_trusttunnel_services "all")
    
    if [ ${#all_services[@]} -eq 0 ]; then
        print_warning "No TrustTunnel services found"
        pause
        return
    fi
    
    for service in "${all_services[@]}"; do
        if [ -n "$service" ]; then
            echo -e "${WHITE}Checking $service...${RESET}"
            
            local status=$(get_service_status "$service")
            case "$status" in
                "active_enabled")
                    echo -e "${GREEN}  ✅ Service is healthy${RESET}"
                    ;;
                "active_disabled")
                    echo -e "${YELLOW}  ⚠️ Service running but auto-start disabled${RESET}"
                    if confirm_action "  Enable auto-start?"; then
                        control_service "enable" "$service"
                        print_success "  Auto-start enabled"
                    fi
                    ;;
                "inactive_enabled")
                    echo -e "${YELLOW}  ⚠️ Service stopped but auto-start enabled${RESET}"
                    if confirm_action "  Start service now?"; then
                        control_service "start" "$service"
                        print_success "  Service started"
                    fi
                    ;;
                "inactive_disabled")
                    echo -e "${RED}  ❌ Service is stopped and disabled${RESET}"
                    if confirm_action "  Enable and start service?"; then
                        control_service "enable" "$service"
                        control_service "start" "$service"
                        print_success "  Service enabled and started"
                    fi
                    ;;
            esac
            echo ""
        fi
    done
    
    pause
}

# ============================================================================
# AUTOMATION FUNCTIONS
# ============================================================================

# Function to setup monitoring
setup_monitoring() {
    clear
    draw_line "$CYAN" "=" 50
    echo -e "${CYAN}        🔄 Setup Service Monitoring${RESET}"
    draw_line "$CYAN" "=" 50
    echo ""
    
    # Create monitoring script
    local monitor_script="/usr/local/bin/trusttunnel-monitor.sh"
    cat <<'EOF' | sudo tee "$monitor_script" > /dev/null
#!/bin/bash
LOG_FILE="/var/log/trusttunnel-monitor.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_and_restart_service() {
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

# Check all TrustTunnel services
for service in $(systemctl list-units --type=service --all | grep 'trusttunnel' | awk '{print $1}'); do
    check_and_restart_service "$service"
done

log_message "Service monitoring check completed"
EOF
    
    sudo chmod +x "$monitor_script"
    
    # Setup systemd timer
    cat <<EOF | sudo tee "/etc/systemd/system/trusttunnel-monitor.timer" > /dev/null
[Unit]
Description=TrustTunnel Service Monitor Timer
Requires=trusttunnel-monitor.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    cat <<EOF | sudo tee "/etc/systemd/system/trusttunnel-monitor.service" > /dev/null
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
    print_info "Monitor runs every 5 minutes"
    print_info "Log file: /var/log/trusttunnel-monitor.log"
    
    pause
}

# ============================================================================
# MENU FUNCTIONS
# ============================================================================

# Function to show main menu
show_main_menu() {
    clear
    
    # Show banner
    echo -e "${CYAN}"
    if command_exists figlet; then
        figlet -f slant "TrustTunnel" 2>/dev/null || echo "TrustTunnel Manager"
    else
        echo "TrustTunnel Manager"
    fi
    echo -e "${RESET}"
    
    draw_line "$YELLOW" "=" 60
    echo -e "${YELLOW}Developed by ErfanXRay => https://github.com/Erfan-XRay/TrustTunnel${RESET}"
    echo -e "${YELLOW}Telegram Channel => @Erfan_XRay${RESET}"
    echo -e "${WHITE}Reverse tunnel over QUIC (Based on rstun project)${RESET}"
    draw_line "$GREEN" "=" 60
    
    echo ""
    echo -e "${BOLD_GREEN}📋 MAIN MENU${RESET}"
    echo ""
    echo -e "  ${YELLOW}1)${RESET} ${WHITE}🔧 Installation & Setup${RESET}"
    echo -e "  ${YELLOW}2)${RESET} ${WHITE}🌐 Service Management${RESET}"
    echo -e "  ${YELLOW}3)${RESET} ${WHITE}📊 Monitoring & Maintenance${RESET}"
    echo -e "  ${YELLOW}4)${RESET} ${WHITE}🛠️ Tools & Utilities${RESET}"
    echo ""
    echo -e "  ${YELLOW}0)${RESET} ${RED}Exit${RESET}"
    echo ""
    draw_line "$GREEN" "-" 60
    echo -e "${WHITE}Your choice:${RESET} "
}

# Function to show installation menu
show_installation_menu() {
    while true; do
        clear
        draw_line "$CYAN" "=" 50
        echo -e "${CYAN}        🔧 Installation & Setup${RESET}"
        draw_line "$CYAN" "=" 50
        echo ""
        
        echo -e "${WHITE}Select option:${RESET}"
        echo -e "  ${YELLOW}1)${RESET} Install TrustTunnel"
        echo -e "  ${YELLOW}2)${RESET} Uninstall TrustTunnel"
        echo -e "  ${YELLOW}0)${RESET} Return to main menu"
        echo ""
        echo -e "${WHITE}Your choice:${RESET} "
        read -r choice
        
        case $choice in
            1) install_trusttunnel ;;
            2) uninstall_trusttunnel ;;
            0) break ;;
            *) print_error "Invalid choice"; pause ;;
        esac
    done
}

# Function to show service management menu
show_service_management_menu() {
    while true; do
        clear
        draw_line "$GREEN" "=" 50
        echo -e "${GREEN}        🌐 Service Management${RESET}"
        draw_line "$GREEN" "=" 50
        echo ""
        
        echo -e "${WHITE}Select option:${RESET}"
        echo -e "  ${YELLOW}1)${RESET} Add Server (Iran)"
        echo -e "  ${YELLOW}2)${RESET} Add Client (Kharej)"
        echo -e "  ${YELLOW}3)${RESET} Quick Service Operations"
        echo -e "  ${YELLOW}0)${RESET} Return to main menu"
        echo ""
        echo -e "${WHITE}Your choice:${RESET} "
        read -r choice
        
        case $choice in
            1) add_server ;;
            2) add_client ;;
            3) quick_service_operations ;;
            0) break ;;
            *) print_error "Invalid choice"; pause ;;
        esac
    done
}

# Function to show monitoring menu
show_monitoring_menu() {
    while true; do
        clear
        draw_line "$BLUE" "=" 50
        echo -e "${BLUE}        📊 Monitoring & Maintenance${RESET}"
        draw_line "$BLUE" "=" 50
        echo ""
        
        echo -e "${WHITE}Select option:${RESET}"
        echo -e "  ${YELLOW}1)${RESET} Service Overview"
        echo -e "  ${YELLOW}2)${RESET} Setup Monitoring"
        echo -e "  ${YELLOW}3)${RESET} View Service Logs"
        echo -e "  ${YELLOW}0)${RESET} Return to main menu"
        echo ""
        echo -e "${WHITE}Your choice:${RESET} "
        read -r choice
        
        case $choice in
            1) show_service_overview ;;
            2) setup_monitoring ;;
            3) show_logs_menu ;;
            0) break ;;
            *) print_error "Invalid choice"; pause ;;
        esac
    done
}

# Function to show tools menu
show_tools_menu() {
    while true; do
        clear
        draw_line "$MAGENTA" "=" 50
        echo -e "${MAGENTA}        🛠️ Tools & Utilities${RESET}"
        draw_line "$MAGENTA" "=" 50
        echo ""
        
        echo -e "${WHITE}Select option:${RESET}"
        echo -e "  ${YELLOW}1)${RESET} Port Management"
        echo -e "  ${YELLOW}2)${RESET} Connection Test"
        echo -e "  ${YELLOW}3)${RESET} System Information"
        echo -e "  ${YELLOW}0)${RESET} Return to main menu"
        echo ""
        echo -e "${WHITE}Your choice:${RESET} "
        read -r choice
        
        case $choice in
            1) show_port_management_menu ;;
            2) test_connection ;;
            3) show_system_info ;;
            0) break ;;
            *) print_error "Invalid choice"; pause ;;
        esac
    done
}

# Function to show service logs menu
show_logs_menu() {
    while true; do
        clear
        draw_line "$BLUE" "=" 50
        echo -e "${BLUE}        📋 Service Logs${RESET}"
        draw_line "$BLUE" "=" 50
        echo ""
        
        mapfile -t all_services < <(get_trusttunnel_services "all")
        
        if [ ${#all_services[@]} -eq 0 ]; then
            print_warning "No TrustTunnel services found"
            pause
            return
        fi
        
        echo -e "${WHITE}Select service to view logs:${RESET}"
        for i in "${!all_services[@]}"; do
            if [ -n "${all_services[i]}" ]; then
                echo -e "  ${YELLOW}$((i+1)))${RESET} ${all_services[i]}"
            fi
        done
        echo -e "  ${YELLOW}0)${RESET} Return to main menu"
        echo ""
        echo -e "${WHITE}Your choice:${RESET} "
        read -r choice
        
        if [[ "$choice" == "0" ]]; then
            break
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#all_services[@]} ]; then
            local selected_service="${all_services[$((choice-1))]}"
            if [ -n "$selected_service" ]; then
                show_service_logs "$selected_service"
            fi
        else
            print_error "Invalid choice"
            pause
        fi
    done
}

# Function to show port management menu
show_port_management_menu() {
    while true; do
        clear
        draw_line "$MAGENTA" "=" 50
        echo -e "${MAGENTA}        🔌 Port Management${RESET}"
        draw_line "$MAGENTA" "=" 50
        echo ""
        
        local firewall_type=$(detect_firewall)
        echo -e "${WHITE}Detected firewall: ${CYAN}$firewall_type${RESET}"
        echo ""
        
        echo -e "${WHITE}Select operation:${RESET}"
        echo -e "  ${YELLOW}1)${RESET} Open a port"
        echo -e "  ${YELLOW}2)${RESET} Close a port"
        echo -e "  ${YELLOW}3)${RESET} Check port status"
        echo -e "  ${YELLOW}4)${RESET} Show all open ports"
        echo -e "  ${YELLOW}5)${RESET} Auto-fix firewall issues"
        echo -e "  ${YELLOW}0)${RESET} Return to main menu"
        echo ""
        echo -e "${WHITE}Your choice:${RESET} "
        read -r choice
        
        case $choice in
            1)
                echo -e "${WHITE}Enter port number:${RESET} "
                read -r port
                if validate_port "$port"; then
                    echo -e "${WHITE}Protocol (tcp/udp/both):${RESET} "
                    read -r protocol
                    if [[ "$protocol" =~ ^(tcp|udp|both)$ ]]; then
                        manage_firewall_port "open" "$port" "$protocol"
                        print_success "Port $port ($protocol) opened"
                    else
                        print_error "Invalid protocol"
                    fi
                else
                    print_error "Invalid port number"
                fi
                pause
                ;;
            2)
                echo -e "${WHITE}Enter port number:${RESET} "
                read -r port
                if validate_port "$port"; then
                    echo -e "${WHITE}Protocol (tcp/udp/both):${RESET} "
                    read -r protocol
                    if [[ "$protocol" =~ ^(tcp|udp|both)$ ]]; then
                        manage_firewall_port "close" "$port" "$protocol"
                        print_success "Port $port ($protocol) closed"
                    else
                        print_error "Invalid protocol"
                    fi
                else
                    print_error "Invalid port number"
                fi
                pause
                ;;
            3)
                echo -e "${WHITE}Enter port number:${RESET} "
                read -r port
                if validate_port "$port"; then
                    local tcp_status=$(check_port_status "$port" "tcp")
                    local udp_status=$(check_port_status "$port" "udp")
                    echo -e "${WHITE}Port $port status:${RESET}"
                    echo -e "  TCP: $tcp_status"
                    echo -e "  UDP: $udp_status"
                else
                    print_error "Invalid port number"
                fi
                pause
                ;;
            4)
                case "$firewall_type" in
                    "ufw")
                        echo -e "${CYAN}UFW Status:${RESET}"
                        sudo ufw status
                        ;;
                    "iptables")
                        echo -e "${CYAN}iptables Rules:${RESET}"
                        sudo iptables -L INPUT -n --line-numbers | head -20
                        ;;
                    *)
                        print_warning "No firewall detected"
                        ;;
                esac
                pause
                ;;
            5)
                auto_fix_firewall
                ;;
            0)
                break
                ;;
            *)
                print_error "Invalid choice"
                pause
                ;;
        esac
    done
}

# Function to auto-fix firewall issues
auto_fix_firewall() {
    clear
    draw_line "$CYAN" "=" 50
    echo -e "${CYAN}        🔧 Auto-Fix Firewall Issues${RESET}"
    draw_line "$CYAN" "=" 50
    echo ""
    
    local firewall_type=$(detect_firewall)
    
    if [ "$firewall_type" = "ufw" ]; then
        print_info "Checking UFW status"
        if ! sudo ufw status | grep -q "Status: active"; then
            if confirm_action "UFW is inactive. Enable it?"; then
                sudo ufw --force enable
                print_success "UFW enabled"
            fi
        fi
        
        if confirm_action "Reload UFW rules?"; then
            sudo ufw reload
            print_success "UFW rules reloaded"
        fi
    fi
    
    if confirm_action "Save iptables rules?"; then
        if command_exists iptables-save && command_exists netfilter-persistent; then
            sudo netfilter-persistent save
        elif [ -f /etc/iptables/rules.v4 ]; then
            sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
        fi
        print_success "iptables rules saved"
    fi
    
    pause
}

# Function to test connection
test_connection() {
    clear
    draw_line "$CYAN" "=" 50
    echo -e "${CYAN}        🔍 Connection Test${RESET}"
    draw_line "$CYAN" "=" 50
    echo ""
    
    echo -e "${WHITE}Enter server address:${RESET} "
    read -r server
    
    echo -e "${WHITE}Enter port (default: 6060):${RESET} "
    read -r port
    port=${port:-6060}
    
    if [ -z "$server" ] || ! validate_port "$port"; then
        print_error "Invalid input"
        pause
        return
    fi
    
    echo ""
    print_info "Testing connection to $server:$port"
    
    # TCP connection test
    if timeout 10 bash -c "echo >/dev/tcp/$server/$port" 2>/dev/null; then
        print_success "TCP connection successful"
    else
        print_error "TCP connection failed"
    fi
    
    # Ping test
    print_info "Testing ping"
    if ping -c 3 "$server" >/dev/null 2>&1; then
        print_success "Ping successful"
    else
        print_error "Ping failed"
    fi
    
    # DNS resolution
    print_info "Testing DNS resolution"
    if nslookup "$server" >/dev/null 2>&1; then
        print_success "DNS resolution successful"
    else
        print_error "DNS resolution failed"
    fi
    
    pause
}

# Function to show system information
show_system_info() {
    clear
    draw_line "$CYAN" "=" 50
    echo -e "${CYAN}        💻 System Information${RESET}"
    draw_line "$CYAN" "=" 50
    echo ""
    
    echo -e "${BOLD_YELLOW}🖥️ System Details${RESET}"
    echo -e "${WHITE}Hostname: $(hostname)${RESET}"
    echo -e "${WHITE}OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")${RESET}"
    echo -e "${WHITE}Kernel: $(uname -r)${RESET}"
    echo -e "${WHITE}Architecture: $(uname -m)${RESET}"
    echo -e "${WHITE}Uptime: $(uptime -p 2>/dev/null || uptime | cut -d',' -f1)${RESET}"
    
    echo ""
    echo -e "${BOLD_YELLOW}💾 Resources${RESET}"
    free -h | grep -E "Mem|Swap" | while read line; do
        echo -e "${WHITE}$line${RESET}"
    done
    
    echo ""
    echo -e "${BOLD_YELLOW}🌐 Network${RESET}"
    echo -e "${WHITE}Public IP: $(curl -s ifconfig.me 2>/dev/null || echo "Unable to detect")${RESET}"
    echo -e "${WHITE}Local IP: $(hostname -I | awk '{print $1}' 2>/dev/null || echo "Unable to detect")${RESET}"
    
    echo ""
    echo -e "${BOLD_YELLOW}🔧 TrustTunnel Status${RESET}"
    if [ -d "rstun" ]; then
        print_success "TrustTunnel installed"
        [ -f "rstun/rstund" ] && echo -e "${WHITE}Server binary: Available${RESET}"
        [ -f "rstun/rstunc" ] && echo -e "${WHITE}Client binary: Available${RESET}"
    else
        print_error "TrustTunnel not installed"
    fi
    
    # Service count
    local server_count=0
    local client_count=0
    
    [ -f "/etc/systemd/system/trusttunnel.service" ] && server_count=1
    client_count=$(get_trusttunnel_services "client" | wc -l)
    
    echo -e "${WHITE}Configured servers: $server_count${RESET}"
    echo -e "${WHITE}Configured clients: $client_count${RESET}"
    
    pause
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

main() {
    # Initialize
    set -e
    
    # Create log file
    sudo touch "$LOG_FILE" 2>/dev/null || true
    sudo chmod 666 "$LOG_FILE" 2>/dev/null || true
    
    log_message "INFO" "TrustTunnel Manager started"
    
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
    
    # Main menu loop
    while true; do
        show_main_menu
        read -r choice
        
        case $choice in
            1) show_installation_menu ;;
            2) show_service_management_menu ;;
            3) show_monitoring_menu ;;
            4) show_tools_menu ;;
            0)
                echo -e "${GREEN}👋 Goodbye!${RESET}"
                log_message "INFO" "TrustTunnel Manager exited"
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                pause
                ;;
        esac
    done
}

# Run main function
main "$@"
