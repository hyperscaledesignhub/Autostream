# EBS CSI Driver for gp3 storage support
# Note: EBS CSI driver is now configured in eks_cluster.tf as part of cluster_addons
# This file is kept for backward compatibility but the addon is managed by the EKS module

# Output
output "ebs_csi_driver_installed" {
  description = "Whether EBS CSI driver addon is installed"
  value       = var.install_ebs_csi_driver
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = var.install_ebs_csi_driver ? module.ebs_csi_irsa[0].iam_role_arn : null
}

