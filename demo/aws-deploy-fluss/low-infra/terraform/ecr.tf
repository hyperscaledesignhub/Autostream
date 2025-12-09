# ECR Repository for demo application (used by both producer and flink aggregator)
# Note: Run ./import-ecr.sh before terraform apply if repositories already exist
resource "aws_ecr_repository" "demo_app" {
  name                 = "fluss-demo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "fluss-demo"
    Environment = var.environment
  }

  lifecycle {
    # Ignore changes to tags after initial creation to avoid conflicts
    ignore_changes = [tags]
  }
}

# ECR Lifecycle Policy for demo app
resource "aws_ecr_lifecycle_policy" "demo_app" {
  repository = aws_ecr_repository.demo_app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR Repository for Fluss (Apache Fluss image)
# Note: Run ./import-ecr.sh before terraform apply if repositories already exist
resource "aws_ecr_repository" "fluss" {
  name                 = "fluss"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "fluss"
    Environment = var.environment
  }

  lifecycle {
    # Ignore changes to tags after initial creation to avoid conflicts
    ignore_changes = [tags]
  }
}

# ECR Lifecycle Policy for Fluss
resource "aws_ecr_lifecycle_policy" "fluss" {
  repository = aws_ecr_repository.fluss.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Output ECR repository URLs
output "ecr_repository_url" {
  description = "ECR repository URL for demo application"
  value       = aws_ecr_repository.demo_app.repository_url
}

output "ecr_fluss_repository_url" {
  description = "ECR repository URL for Fluss image"
  value       = aws_ecr_repository.fluss.repository_url
}

