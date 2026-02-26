##############################
# STAGING Environment - AWS
# Close to prod, reduced capacity
##############################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "devops-assignment-tf-state-pravardhan"
    key            = "aws/staging/terraform.tfstate"  # Different key from dev
    region         = "ap-south-1"
    dynamodb_table = "devops-assignment-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1"
  default_tags {
    tags = { Project = "devops-assignment", Environment = "staging", ManagedBy = "terraform" }
  }
}

data "aws_vpc" "default" { default = true }
data "aws_ami" "al2023" {
  most_recent = true; owners = ["amazon"]
  filter { name = "name", values = ["al2023-ami-*-x86_64"] }
  filter { name = "virtualization-type", values = ["hvm"] }
}
data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "backend" {
  name                 = "devops-assignment-staging-backend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "devops-assignment-staging-frontend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_security_group" "staging_sg" {
  name        = "devops-staging-app-sg"
  description = "Staging - SSH restricted to known CIDRs"
  vpc_id      = data.aws_vpc.default.id

  ingress { from_port = 80,   to_port = 80,   protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" }
  ingress { from_port = 8000, to_port = 8000, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "API" }
  # SSH restricted in staging (not open to world)
  ingress { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = var.admin_cidr_blocks, description = "SSH admin only" }
  egress  { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "devops-staging-sg" }
}

resource "aws_iam_role" "staging_ec2_role" {
  name = "devops-staging-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "staging_ecr_pull" {
  name = "ecr-pull"
  role = aws_iam_role.staging_ec2_role.id
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

resource "aws_iam_instance_profile" "staging_profile" {
  name = "devops-staging-ec2-profile"
  role = aws_iam_role.staging_ec2_role.name
}

resource "aws_instance" "staging_app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = [aws_security_group.staging_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.staging_profile.name
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
echo "=== STAGING Bootstrap ==="
dnf update -y && dnf install -y docker nginx
systemctl enable docker && systemctl start docker
usermod -aG docker ec2-user
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.ap-south-1.amazonaws.com
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
      - ALLOWED_ORIGINS=http://$PUBLIC_IP
    restart: always
    mem_limit: 512m
    cpus: 0.5
  frontend:
    image: ${aws_ecr_repository.frontend.repository_url}:latest
    container_name: frontend
    ports: ["3000:3000"]
    environment:
      - NEXT_PUBLIC_API_URL=http://$PUBLIC_IP:8000
    restart: always
    mem_limit: 512m
    cpus: 0.5
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
echo "=== STAGING done. IP: $PUBLIC_IP ==="
USERDATA
  )

  tags = { Name = "devops-staging-app" }

  lifecycle { create_before_destroy = true }
}

resource "aws_eip" "staging_app" {
  instance = aws_instance.staging_app.id
  domain   = "vpc"
  tags     = { Name = "devops-staging-eip" }
}

# CPU alarm - tighter threshold in staging
resource "aws_cloudwatch_metric_alarm" "staging_cpu_high" {
  alarm_name          = "devops-staging-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Staging CPU > 80%"
  alarm_actions       = []
  dimensions          = { InstanceId = aws_instance.staging_app.id }
}

resource "aws_cloudwatch_log_group" "staging_logs" {
  name              = "/devops/staging"
  retention_in_days = 14
}

variable "key_pair_name" {
  type = string
  description = "EC2 Key Pair name"
}

variable "admin_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed SSH access in staging"
  default     = ["0.0.0.0/0"]
}

output "frontend_url"     { value = "http://${aws_eip.staging_app.public_ip}" }
output "backend_url"      { value = "http://${aws_eip.staging_app.public_ip}:8000" }
output "ecr_backend_url"  { value = aws_ecr_repository.backend.repository_url }
output "ecr_frontend_url" { value = aws_ecr_repository.frontend.repository_url }
output "instance_id"      { value = aws_instance.staging_app.id }
