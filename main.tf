locals {
  // Get distinct list of domains and SANs
  distinct_domain_names = distinct([for s in concat([var.domain_name], var.subject_alternative_names) : replace(s, "*.", "")])

  // Copy domain_validation_options for the distinct domain names
  domain_validation_options = { for k, v in aws_acm_certificate.this[0].domain_validation_options : replace(v.domain_name, "*.", "") => tomap(v) }
  validation_domains        = var.create_certificate ? [for fqdn in local.distinct_domain_names : merge(local.domain_validation_options[fqdn], { "fqdn" = fqdn }) if lookup(local.domain_validation_options, fqdn, null) != null] : []
}

resource "aws_acm_certificate" "this" {
  count = var.create_certificate ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = var.validation_method

  tags = var.tags

  lifecycle {
    create_before_destroy = true
    # https://github.com/terraform-providers/terraform-provider-aws/issues/8531
    ignore_changes = [subject_alternative_names]
  }
}

resource "aws_route53_record" "validation" {
  count = var.create_certificate && var.validation_method == "DNS" && var.validate_certificate ? length(local.distinct_domain_names) : 0

  zone_id = lookup(var.alternate_zone_ids, local.validation_domains[count.index]["fqdn"], var.zone_id)
  name    = local.validation_domains[count.index]["resource_record_name"]
  type    = local.validation_domains[count.index]["resource_record_type"]
  ttl     = 60

  records = [
    local.validation_domains[count.index]["resource_record_value"]
  ]

  allow_overwrite = var.validation_allow_overwrite_records

  depends_on = [aws_acm_certificate.this]
}

resource "aws_acm_certificate_validation" "this" {
  count = var.create_certificate && var.validation_method == "DNS" && var.validate_certificate && var.wait_for_validation ? 1 : 0

  certificate_arn = aws_acm_certificate.this[0].arn

  validation_record_fqdns = aws_route53_record.validation.*.fqdn
}
