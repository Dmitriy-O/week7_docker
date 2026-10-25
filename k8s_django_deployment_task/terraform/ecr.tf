resource "aws_ecr_repository" "application" {
  name                 = local.project_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

output "ecr_repository_url" {
  description = "Private ECR repository URL for the Django application"
  value       = aws_ecr_repository.application.repository_url
}
