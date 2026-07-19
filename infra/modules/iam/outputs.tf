output "irsa_role_arns" {
  value = { for k, v in aws_iam_role.irsa : k => v.arn }
}

output "eso_role_arns" {
  value = { for k, v in aws_iam_role.eso : k => v.arn }
}

output "ebs_csi_driver_role_arn" {
  value = aws_iam_role.ebs_csi_driver.arn
}

output "ci_nonprod_role_arn" {
  value = try(aws_iam_role.ci_nonprod[0].arn, null)
}

output "ci_production_promotion_role_arn" {
  value = try(aws_iam_role.ci_production_promotion[0].arn, null)
}
