#!/bin/bash

# My TLS Certificate Generator By Wilecurity

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'


print_status() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}      TLS Certificate Generator - Let's Encrypt${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}


if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use sudo)"
    exit 1
fi


clear

print_header

echo -e "${YELLOW}Enter your domain name:${NC}"
read -p "Domain (e.g., example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    print_error "Domain name cannot be empty"
    exit 1
fi


echo ""
echo -e "${YELLOW}Enter your email address (for certificate notifications):${NC}"
read -p "Email: " EMAIL

if [ -z "$EMAIL" ]; then
    print_error "Email cannot be empty"
    exit 1
fi

echo ""
print_status "Please confirm your details:"
echo "  Domain: $DOMAIN"
echo "  Email:  $EMAIL"
echo ""
read -p "Is this correct? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Setup cancelled"
    exit 1
fi

print_status "Starting TLS certificate generation for $DOMAIN"


if ! command -v certbot &> /dev/null; then
    print_warning "Certbot not found. Installing with verbose output..."
    echo ""
    print_info "Updating package lists..."
    apt-get update -y -qq 2>&1 | while read line; do echo "    $line"; done
    echo ""
    print_info "Installing certbot and dependencies..."
    apt-get install -y certbot python3-certbot 2>&1 | while read line; do echo "    $line"; done
    print_success "Certbot installed successfully"
    echo ""
else
    print_success "Certbot is already installed"
    print_info "Certbot version: $(certbot --version)"
    echo ""
fi

print_info "Certbot location: $(which certbot)"
echo ""


if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    print_warning "Certificate already exists for $DOMAIN"
    print_info "Current certificate info:"
    if [ -f "/etc/letsencrypt/live/$DOMAIN/cert.pem" ]; then
        openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" -text -noout | grep -E "Subject:|Not Before:|Not After :"
    fi
    echo ""
    read -p "Do you want to renew/replace it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Exiting..."
        exit 0
    fi
fi

print_status "Requesting certificate..."
print_warning "Prepare to add a DNS TXT record when prompted"
print_info "You will need access to your DNS management panel"
echo ""


print_info "Running certbot with manual DNS challenge..."
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

sudo certbot certonly --manual \
    --preferred-challenges=dns \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    --domains "*.$DOMAIN" \
    --domains "$DOMAIN" \
    --verbose


CERTBOT_EXIT=$?

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

if [ $CERTBOT_EXIT -eq 0 ]; then
    print_success "Certificate generated successfully!"
    echo ""
    print_status "Certificate details:"
    echo "  Location: /etc/letsencrypt/live/$DOMAIN/"
    echo "  Fullchain: /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    echo "  Private key: /etc/letsencrypt/live/$DOMAIN/privkey.pem"
    echo "  Certificate: /etc/letsencrypt/live/$DOMAIN/cert.pem"
    echo "  Chain: /etc/letsencrypt/live/$DOMAIN/chain.pem"
    echo ""
    
    print_info "Verifying certificate files:"
    for file in fullchain.pem privkey.pem cert.pem chain.pem; do
        if [ -f "/etc/letsencrypt/live/$DOMAIN/$file" ]; then
            echo -e "  ${GREEN}✓${NC} $file exists"
        else
            echo -e "  ${RED}✗${NC} $file missing"
        fi
    done
    echo ""
    
    EXPIRY=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" 2>/dev/null | cut -d= -f2)
    if [ -n "$EXPIRY" ]; then
        print_status "Certificate expires: $EXPIRY"
        
      
        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
        NOW_EPOCH=$(date +%s)
        DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
        echo -e "  ${GREEN}Days until expiry: $DAYS_LEFT${NC}"
    fi
    
 
    echo ""
    print_info "Testing certificate verification:"
    if openssl verify -untrusted "/etc/letsencrypt/live/$DOMAIN/chain.pem" "/etc/letsencrypt/live/$DOMAIN/cert.pem" 2>/dev/null; then
        print_success "Certificate verification passed"
    else
        print_warning "Certificate verification had issues"
    fi
    
    echo ""
    print_status "Add this to your Muraena config.toml:"
    echo ""
    echo -e "${GREEN}[tls]"
    echo "    enable = true"
    echo "    expand = false"
    echo "    certificate = \"/etc/letsencrypt/live/$DOMAIN/fullchain.pem\""
    echo "    key = \"/etc/letsencrypt/live/$DOMAIN/privkey.pem\""
    echo "    root = \"/etc/letsencrypt/live/$DOMAIN/fullchain.pem\"${NC}"
    echo ""
    
    read -p "Show full certificate details? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Certificate details:"
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
        openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/cert.pem" -text -noout
        echo -e "${CYAN}───────────────────────────────────────────────────────────${NC}"
    fi
    
    
    echo ""
    read -p "Test certificate with curl? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Testing certificate with curl..."
        curl -vI "https://$DOMAIN" 2>&1 | grep -E "subject:|issuer:|expire date:|SSL certificate verify"
    fi
    
else
    print_error "Certificate generation failed (exit code: $CERTBOT_EXIT)"
    echo ""
    print_info "Common issues:"
    echo "  1. DNS TXT record not added correctly"
    echo "  2. DNS propagation delay (wait 1-2 minutes)"
    echo "  3. Firewall blocking certbot"
    echo "  4. Invalid domain or email"
    echo ""
    print_status "Try again after verifying your DNS settings"
    exit 1
fi

print_success "Setup complete!"
