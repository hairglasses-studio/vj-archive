terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.36"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# S3 Bucket for VJ Archive
resource "aws_s3_bucket" "vj_archive" {
  bucket = var.bucket_name

  tags = {
    Project     = "vj-archive"
    Owner       = "aftrs-studio"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "vj_archive" {
  bucket = aws_s3_bucket.vj_archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for accidental deletion protection
resource "aws_s3_bucket_versioning" "vj_archive" {
  bucket = aws_s3_bucket.vj_archive.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "vj_archive" {
  bucket = aws_s3_bucket.vj_archive.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Intelligent-Tiering configuration
resource "aws_s3_bucket_intelligent_tiering_configuration" "archive" {
  bucket = aws_s3_bucket.vj_archive.id
  name   = "EntireArchive"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

# Lifecycle rule - delete old versions after 30 days
resource "aws_s3_bucket_lifecycle_configuration" "vj_archive" {
  bucket = aws_s3_bucket.vj_archive.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# IAM policy for vj-archive access
resource "aws_iam_policy" "vj_archive_access" {
  name        = "vj-archive-access"
  description = "Policy for accessing the VJ archive S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.vj_archive.arn
      },
      {
        Sid    = "ObjectOperations"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:RestoreObject"
        ]
        Resource = "${aws_s3_bucket.vj_archive.arn}/*"
      }
    ]
  })
}

# IAM user for rclone access (optional - can use existing profile)
resource "aws_iam_user" "vj_archive_sync" {
  count = var.create_iam_user ? 1 : 0
  name  = "vj-archive-sync"

  tags = {
    Project   = "vj-archive"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_user_policy_attachment" "vj_archive_sync" {
  count      = var.create_iam_user ? 1 : 0
  user       = aws_iam_user.vj_archive_sync[0].name
  policy_arn = aws_iam_policy.vj_archive_access.arn
}
