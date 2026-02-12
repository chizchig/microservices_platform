output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group ID of the cluster"
  value       = aws_security_group.cluster.id
}

output "node_group_security_group_id" {
  description = "Security group ID of node groups"
  value       = aws_security_group.node_group.id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.main.arn
}

output "oidc_provider_url" {
  description = "OIDC provider URL"
  value       = aws_iam_openid_connect_provider.main.url
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the cluster"
  value       = aws_iam_role.cluster.arn
}

output "node_group_iam_role_arn" {
  description = "IAM role ARN of node groups"
  value       = aws_iam_role.node_group.arn
}

output "kms_key_arn" {
  description = "KMS key ARN for encryption"
  value       = aws_kms_key.eks.arn
}
