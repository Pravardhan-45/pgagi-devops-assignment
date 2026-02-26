output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Elastic IP of the EC2 instance"
  value       = aws_eip.app.public_ip
}

output "public_dns" {
  description = "Public DNS name"
  value       = aws_eip.app.public_dns
}

output "frontend_url" {
  description = "Frontend application URL"
  value       = "http://${aws_eip.app.public_ip}"
}

output "backend_url" {
  description = "Backend API URL"
  value       = "http://${aws_eip.app.public_ip}:8000"
}

output "ecr_backend_url" {
  description = "ECR repository URL for backend"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_url" {
  description = "ECR repository URL for frontend"
  value       = aws_ecr_repository.frontend.repository_url
}
