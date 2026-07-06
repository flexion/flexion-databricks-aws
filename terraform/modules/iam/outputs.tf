output "cross_account_role_arn" {
  value = aws_iam_role.cross_account.arn
}

output "cross_account_policy_id" {
  value = aws_iam_role_policy.cross_account.id
}
