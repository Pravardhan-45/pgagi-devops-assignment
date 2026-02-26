##############################
# DEV Environment - AWS
# Minimal resources, cost-optimized
##############################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in S3 (state file per environment)
  backend "s3" {
    bucket         = "devops-assignment-tf-state-pravardhan"
    key            = "aws/dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "devops-assignment-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      Project     = "devops-assignment"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "pravardhan-45"
    }
  }
}

# Create ECR repos first (before first deploy)
resource "aws_ecr_repository" "backend" {
  name                 = "devops-assignment-dev-backend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "devops-assignment-dev-frontend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({ rules = [{ rulePriority = 1, description = "Keep 3 images",
    selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 3 },
    action = { type = "expire" } }] })
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
  policy = jsonencode({ rules = [{ rulePriority = 1, description = "Keep 3 images",
    selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 3 },
    action = { type = "expire" } }] })
}

# Networking: use default VPC for dev (no cost)
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter { name = "vpc-id", values = [data.aws_vpc.default.id] }
}

# Security group
resource "aws_security_group" "dev_app_sg" {
  name        = "devops-dev-app-sg"
  description = "Dev environment - open for testing"
  vpc_id      = data.aws_vpc.default.id

  ingress { from_port = 80,  to_port = 80,   protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" }
  ingress { from_port = 8000, to_port = 8000, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "Backend API" }
  ingress { from_port = 3000, to_port = 3000, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "Frontend" }
  # SSH open in dev for easy debugging (locked down in staging/prod)
  ingress { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "SSH - dev only" }
  egress  { from_port = 0,  to_port = 0,  protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "devops-dev-app-sg" }
}

# IAM Role
resource "aws_iam_role" "dev_ec2_role" {
  name = "devops-dev-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "dev_ecr_pull" {
  name = "ecr-pull"
  role = aws_iam_role.dev_ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "dev_profile" {
  name = "devops-dev-ec2-profile"
  role = aws_iam_role.dev_ec2_role.name
}

# EC2 - Free Tier t2.micro
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter { name = "name", values = ["al2023-ami-*-x86_64"] }
  filter { name = "virtualization-type", values = ["hvm"] }
}

data "aws_caller_identity" "current" {}
locals {
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_instance" "dev_app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"           # Free tier
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = [aws_security_group.dev_app_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.dev_profile.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(<<-USERDATA
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "=== DEV Bootstrap starting ==="
dnf update -y
dnf install -y docker nginx
systemctl enable docker && systemctl start docker
usermod -aG docker ec2-user
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.ap-south-1.amazonaws.com
mkdir -p /opt/app
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
cat > /opt/app/docker-compose.yml <<COMPOSE
version: '3.8'
services:
  backend:
    image: ${aws_ecr_repository.backend.repository_url}:latest
    container_name: backend
    ports: ["8000:8000"]
    environment:
      - ALLOWED_ORIGINS=*
    restart: always
  frontend:
    image: ${aws_ecr_repository.frontend.repository_url}:latest
    container_name: frontend
    ports: ["3000:3000"]
    environment:
      - NEXT_PUBLIC_API_URL=http://$PUBLIC_IP:8000
    restart: always
COMPOSE
curl -SL https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64 \
  -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
cd /opt/app && docker-compose up -d
cat > /etc/nginx/conf.d/app.conf <<NGINX
server {
  listen 80;
  location / { proxy_pass http://localhost:3000; proxy_set_header Host \$host; }
  location /api/ { proxy_pass http://localhost:8000/api/; }
}
NGINX
nginx -t && systemctl enable nginx && systemctl start nginx
echo "=== DEV Bootstrap done. IP: $PUBLIC_IP ==="
USERDATA
  )

  tags = { Name = "devops-dev-app" }
}

resource "aws_eip" "dev_app" {
  instance = aws_instance.dev_app.id
  domain   = "vpc"
  tags     = { Name = "devops-dev-eip" }
}

# CloudWatch log group (short retention in dev)
resource "aws_cloudwatch_log_group" "dev_logs" {
  name              = "/devops/dev"
  retention_in_days = 3
  tags              = { Name = "devops-dev-logs" }
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

output "frontend_url"       { value = "http://${aws_eip.dev_app.public_ip}" }
output "backend_url"        { value = "http://${aws_eip.dev_app.public_ip}:8000" }
output "nginx_url"          { value = "http://${aws_eip.dev_app.public_ip}" }
output "ecr_backend_url"    { value = aws_ecr_repository.backend.repository_url }
output "ecr_frontend_url"   { value = aws_ecr_repository.frontend.repository_url }
output "instance_id"        { value = aws_instance.dev_app.id }
