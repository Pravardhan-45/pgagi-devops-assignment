#!/bin/bash
set -e

# Logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== DevOps Assignment Bootstrap: ${environment} ==="
echo "Starting at $(date)"

# Update system
dnf update -y

# Install Docker
dnf install -y docker nginx
systemctl enable docker
systemctl start docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Install AWS CLI (already present on AL2023)
# Login to ECR
aws ecr get-login-password --region ${aws_region} | \
  docker login --username AWS --password-stdin ${account_id}.dkr.ecr.${aws_region}.amazonaws.com

# Pull latest images
docker pull ${backend_image}:latest
docker pull ${frontend_image}:latest

# Create app directory
mkdir -p /opt/devops-app
cat > /opt/devops-app/docker-compose.yml <<'COMPOSE_EOF'
version: '3.8'
services:
  backend:
    image: ${backend_image}:latest
    container_name: backend
    ports:
      - "8000:8000"
    environment:
      - ALLOWED_ORIGINS=*
    restart: always
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s

  frontend:
    image: ${frontend_image}:latest
    container_name: frontend
    ports:
      - "3000:3000"
    environment:
      - NEXT_PUBLIC_API_URL=http://INSTANCE_IP:8000
    depends_on:
      backend:
        condition: service_healthy
    restart: always
COMPOSE_EOF

# Install docker-compose
curl -SL https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64 \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Get public IP and update compose file
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
sed -i "s/INSTANCE_IP/$PUBLIC_IP/g" /opt/devops-app/docker-compose.yml

# Start services
cd /opt/devops-app
docker-compose up -d

# Configure Nginx as reverse proxy (serves frontend on port 80)
cat > /etc/nginx/conf.d/devops.conf <<'NGINX_EOF'
server {
    listen 80;
    server_name _;

    # Frontend
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # Backend API - proxied under /api
    location /api/ {
        proxy_pass http://localhost:8000/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # Health check
    location /health {
        proxy_pass http://localhost:8000/api/health;
    }
}
NGINX_EOF

nginx -t && systemctl enable nginx && systemctl start nginx

# Create systemd service for app restart on boot
cat > /etc/systemd/system/devops-app.service <<'SERVICE_EOF'
[Unit]
Description=DevOps Assignment App
Requires=docker.service
After=docker.service

[Service]
Restart=always
WorkingDirectory=/opt/devops-app
ExecStartPre=-/usr/local/bin/docker-compose down
ExecStart=/usr/local/bin/docker-compose up
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl enable devops-app

echo "=== Bootstrap complete at $(date) ==="
echo "Frontend: http://$PUBLIC_IP"
echo "Backend:  http://$PUBLIC_IP:8000"
echo "API health: http://$PUBLIC_IP/health"
