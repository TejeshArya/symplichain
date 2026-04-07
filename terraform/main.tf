provider "aws" {
  region = var.aws_region
}

# Web Server EC2 Instance
resource "aws_instance" "web_server" {
  ami           = "ami-0c7217cdde317cfec" # Example AMI (Ubuntu 22.04 LTS)
  instance_type = "t3.medium"
  key_name      = var.key_name

  tags = {
    Name = "Symplichain-Web-${var.environment}"
  }
}

# PostgreSQL Database
resource "aws_db_instance" "postgres" {
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "14"
  instance_class       = "db.t3.micro" # Assuming t3.micro for cost-efficient staging/prod
  db_name              = "symplichain"
  username             = var.db_user
  password             = var.db_password
  skip_final_snapshot  = true

  tags = {
    Name = "Symplichain-DB-${var.environment}"
  }
}

# Redis Database
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "symplichain-redis-${var.environment}"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  engine_version       = "6.x"
  port                 = 6379

  tags = {
    Name = "Symplichain-Redis-${var.environment}"
  }
}

# Frontend S3 Bucket
resource "aws_s3_bucket" "frontend" {
  bucket = "symplichain-frontend-${var.environment}"

  tags = {
    Name = "Symplichain-Frontend-${var.environment}"
  }
}

# CDN for S3 Bucket
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.frontend.id}"
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
