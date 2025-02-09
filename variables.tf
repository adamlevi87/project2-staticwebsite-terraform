# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
  default     = "www.p2-sws.projects-devops.cfd"
}

variable "github_username" {
  description = "Github Username"
  type        = string
  default     = "adamlevi87"
}

variable "repository_name" {
  description = "Name of the repository in github that holds the index.html"
  type        = string
  default     = "project2-staticwebsite-content"
}

variable "repository_branch" {
  description = "Name of the branch of the repository in github that holds the index.html"
  type        = string
  default     = "main"
}

