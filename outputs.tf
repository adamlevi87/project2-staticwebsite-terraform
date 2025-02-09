# ---------------------
# Output DNS Records for SSL Validation
# ---------------------
output "acm_dns_records" {
  value = {
    url = "https://${var.region}.console.aws.amazon.com/acm/home?region=${var.region}#/certificates/${aws_acm_certificate.cert.arn}",
    records = [
      for dvo in aws_acm_certificate.cert.domain_validation_options : {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
      }
    ]
  }

  description = "DNS records required for ACM SSL certificate validation."
}

# ---------------------
# Output DNS Records to point to Cloudfront
# ---------------------
output "dns_records_for_cloudfront" {
  value = {
    domains_to_points_from = aws_cloudfront_distribution.cdn.aliases
    domain_to_point_to = aws_cloudfront_distribution.cdn.domain_name
  }
  description = "DNS records that should be created to point to the cloudfront."
}

# ---------------------
# Github Connection link
# ---------------------
output "complete_github_connection_process_link" {
  value = {
    complete_github_connection_process_link = "https://console.aws.amazon.com/codesuite/settings/connections?connections-meta"
  }
  description = "a link in order to complete github connection to be used in CodePipeline"
}
