#!/bin/bash
set -e

echo "════════════════════════════════════"
echo "  Inception Setup Script"
echo "════════════════════════════════════"

# ─────────────────────────────────────────
# STEP 1: Install Docker
# ─────────────────────────────────────────
echo "Installing Docker..."
sudo apt update
sudo apt install -y curl make git
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
echo "Docker installed!"

# ─────────────────────────────────────────
# STEP 2: Install Docker Compose
# ─────────────────────────────────────────
echo "Installing Docker Compose..."
sudo apt install -y docker-compose-plugin
echo "Docker Compose installed!"

# ─────────────────────────────────────────
# STEP 3: Add domain to /etc/hosts
# ─────────────────────────────────────────
echo "Adding domain to /etc/hosts..."
if ! grep -q "sojammal.42.fr" /etc/hosts; then
    echo "127.0.0.1 sojammal.42.fr" | sudo tee -a /etc/hosts
    echo "Domain added!"
else
    echo "Domain already in /etc/hosts"
fi

# ─────────────────────────────────────────
# STEP 4: Clone project
# ─────────────────────────────────────────

# ─────────────────────────────────────────
# STEP 5: Create secrets
# ─────────────────────────────────────────
echo "Creating secrets..."
mkdir -p secrets
echo "db_password" > secrets/db_password.txt
echo "root_password" > secrets/db_root_password.txt
printf "adminpass\nuserpass\nftppass" > secrets/credentials.txt
echo "Secrets created!"

# ─────────────────────────────────────────
# STEP 6: Create .env
# ─────────────────────────────────────────
echo "Creating .env..."
cat > srcs/.env << EOF
MYSQL_DB=wordpress_db
MYSQL_USER=wp_user
DOMAIN_NAME=sojammal.42.fr
WP_PATH=/var/www/wordpress
WP_ADMIN=sojammal
WP_ADMIN_EMAIL=admin@example.com
WP_USER=hms7rx
WP_USER_EMAIL=user@example.com
FTP_USER=ftpuser
EOF
echo ".env created!"

# ─────────────────────────────────────────
# STEP 7: Reboot for Docker group to take effect
# ─────────────────────────────────────────
echo ""
echo "════════════════════════════════════"
echo "  Setup complete!"
echo "  After reboot run:"
echo "  cd inception && make re"
echo "════════════════════════════════════"
echo ""
echo "Rebooting in 5 seconds..."
sleep 5
sudo reboot
