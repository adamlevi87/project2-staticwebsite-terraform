# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "website" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_object" "index_file" {
  bucket = aws_s3_bucket.website.id     # Reference to the S3 bucket
  key    = "index.html"                 # Path inside the bucket
  source = "index.html"    # Local file to upload
  content_type = "text/html"
  acl    = "private"                     # Set permissions (private, public-read, etc.)
}

resource "aws_s3_bucket_policy" "website_policy" {
  bucket = aws_s3_bucket.website.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.oai.iam_arn]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website.arn}/*"]
  }
}

# ---------------------
# Create CloudFront Origin Access Identity (OAI)
# ---------------------
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for CloudFront and S3 website"
}

# ---------------------
# Request an SSL Certificate (ACM) for Custom Domain
# ---------------------
resource "aws_acm_certificate" "cert" {
  domain_name       = var.bucket_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "null_resource" "dns_records_failure" {
  depends_on = [aws_acm_certificate.cert]
  provisioner "local-exec" {
    interpreter = ["/bin/bash" ,"-c"]
    command = <<-EOT
      echo -e '\\e[31mTerraform is going to fail, you must run Terraform Output and create the required DNS records and then retry\\e[0m'
      echo "use this link: https://${var.region}.console.aws.amazon.com/acm/home?region=${var.region}#/certificates/${aws_acm_certificate.cert.arn}" | sed 's|arn:.*certificate/||'
    EOT
    EOT
  }
}

# ---------------------
# Create CloudFront Distribution with Custom Domain
# ---------------------
resource "aws_cloudfront_distribution" "cdn" {
  depends_on = [null_resource.dns_records_failure]
  origin {
    domain_name = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = "S3Origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  default_root_object = "index.html"

  aliases = [var.bucket_name]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

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
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# ---------------------
# IAM Role for CodePipeline
# ---------------------
resource "aws_iam_role" "codepipeline_role" {
  name = "CodePipelineServiceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_codestarconnections_connection" "github_connection" {
  name          = "github-connection"
  provider_type = "GitHub"
}

resource "aws_iam_policy" "codepipeline_policy" {
  name        = "CodePipelineS3DeployPolicy"
  description = "Allows CodePipeline to access GitHub and S3"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          "${aws_s3_bucket.website.arn}",
          "${aws_s3_bucket.website.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection"]
        Resource = "${aws_codestarconnections_connection.github_connection.arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_attach" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_policy.arn
}

# ---------------------
# AWS CodePipeline
# ---------------------
resource "aws_codepipeline" "s3_deploy" {
  name     = "s3-deploy"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.website.bucket
  }

  stage {
    name = "Source"

    action {
      name             = "GitHubSource"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn    = "${aws_codestarconnections_connection.github_connection.arn}"
        FullRepositoryId = "${var.github_username}/${var.repository_name}"
        BranchName       = var.repository_branch
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "DeployToS3"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      version         = "1"
      input_artifacts = ["SourceArtifact"]

      configuration = {
        BucketName   = aws_s3_bucket.website.bucket
        Extract      = "true"
      }
    }
  }
}

resource "aws_codebuild_project" "filter_files" {
  name         = "filter-files-build"
  service_role = aws_iam_role.codepipeline_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = false
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}
