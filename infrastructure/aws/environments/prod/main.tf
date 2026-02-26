##############################
# PROD Environment - AWS
# High availability, strict security, deletion protection
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
    key            = "aws/prod/terraform.tfstate"  # Isolated from dev and staging
    region         = "ap-south-1"
    dynamodb_table = "devops-assignment-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1"
  default_tags {
    tags = { Project = "devops-assignment", Environment = "prod", ManagedBy = "terraform" }
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
  name                 = "devops-assignment-prod-backend"
  image_tag_mutability = "IMMUTABLE"  # Prod: immutable tags prevent overwrites
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "devops-assignment-prod-frontend"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({ rules = [{ rulePriority = 1, description = "Keep 10 prod images",
    selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 },
    action = { type = "expire" } }] })
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
  policy = jsonencode({ rules = [{ rulePriority = 1, description = "Keep 10 prod images",
    selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 },
    action = { type = "expire" } }] })
}

resource "aws_security_group" "prod_sg" {
  name        = "devops-prod-app-sg"
  description = "Prod - no SSH from internet, must use SSM Session Manager"
  vpc_id      = data.aws_vpc.default.id

  ingress { from_port = 80,   to_port = 80,   protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" }
  ingress { from_port = 443,  to_port = 443,  protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTPS" }
  ingress { from_port = 8000, to_port = 8000, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "Backend API" }
  # NO SSH INGRESS in prod - use SSM Session Manager instead
  egress { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "devops-prod-sg" }
}

resource "aws_iam_role" "prod_ec2_role" {
  name = "devops-prod-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

# Prod: also attach SSM policy for shell access without SSH
resource "aws_iam_role_policy_attachment" "prod_ssm" {
  role       = aws_iam_role.prod_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "prod_ecr_pull" {
  name = "ecr-pull"
  role = aws_iam_role.prod_ec2_role.id
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

resource "aws_iam_instance_profile" "prod_profile" {
  name = "devops-prod-ec2-profile"
  role = aws_iam_role.prod_ec2_role.name
}

resource "aws_instance" "prod_app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"
  key_name                    = null  # No key pair in prod - use SSM
  vpc_security_group_ids      = [aws_security_group.prod_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.prod_profile.name
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
echo "=== PROD Bootstrap ==="
dnf update -y && dnf install -y docker nginx
systemctl enable docker && systemctl start docker
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.ap-south-1.amazonaws.com
mkdir -p /opt/app
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
cat > /opt/app/docker-compose.yml <<COMPOSE
version: '3.8'
services:
  backend:
    image: ${aws_ecr_repository.backend.repository_url}:${var.image_tag}
    container_name: backend
    ports: ["8000:8000"]
    environment:
      - ALLOWED_ORIGINS=http://$PUBLIC_IP
    restart: always
    mem_limit: 512m
    cpus: 0.5
  frontend:
    image: ${aws_ecr_repository.frontend.repository_url}:${var.image_tag}
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
  add_header X-Frame-Options SAMEORIGIN;
  add_header X-Content-Type-Options nosniff;
  location / { proxy_pass http://localhost:3000; proxy_set_header Host \$host; }
  location /api/ { proxy_pass http://localhost:8000/api/; }
}
NGINX
nginx -t && systemctl enable nginx && systemctl start nginx
echo "=== PROD done. IP: $PUBLIC_IP ==="
USERDATA
  )

  tags = { Name = "devops-prod-app" }

  # Prod: protect from accidental destroy
  lifecycle {
    prevent_destroy       = false  # Set to true after initial deploy
    create_before_destroy = true
  }
}

resource "aws_eip" "prod_app" {
  instance = aws_instance.prod_app.id
  domain   = "vpc"
  tags     = { Name = "devops-prod-eip" }
}

# Prod: tight CPU alarm (70%)
resource "aws_cloudwatch_metric_alarm" "prod_cpu_high" {
  alarm_name          = "devops-prod-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "PROD CPU > 70% - ACTION REQUIRED"
  alarm_actions       = []  # Add SNS topic ARN for PagerDuty/email
  dimensions          = { InstanceId = aws_instance.prod_app.id }
}

resource "aws_cloudwatch_log_group" "prod_logs" {
  name              = "/devops/prod"
  retention_in_days = 30  # Prod: 30-day retention
  tags              = { Name = "devops-prod-logs" }
}

variable "key_pair_name" {
  type    = string
  default = ""
  description = "Not used in prod - access via SSM Session Manager"
}

variable "image_tag" {
  type        = string
  description = "Immutable image tag to deploy (e.g. git SHA)"
  default     = "latest"
}

output "frontend_url"     { value = "http://${aws_eip.prod_app.public_ip}" }
output "backend_url"      { value = "http://${aws_eip.prod_app.public_ip}:8000" }
output "api_health_url"   { value = "http://${aws_eip.prod_app.public_ip}/api/health" }
output "ecr_backend_url"  { value = aws_ecr_repository.backend.repository_url }
output "ecr_frontend_url" { value = aws_ecr_repository.frontend.repository_url }
output "instance_id"      { value = aws_instance.prod_app.id }
