# ================================================================================
# EKS CLUSTER CREATION USING TERRAFORM AWS MODULES
# ================================================================================
# This configuration uses terraform-aws-modules/eks/aws and terraform-aws-modules/vpc/aws
# to properly handle node joining and avoid manual aws-auth ConfigMap patching
# ================================================================================

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module - Creates VPC, subnets, NAT gateways, route tables automatically
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.eks_cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)  # EKS requires 2 AZs minimum
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true  # Use single NAT gateway to save costs (all nodes in one AZ)
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"              = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  }

  tags = {
    Name        = "${var.eks_cluster_name}-vpc"
    Project     = "fluss-deployment"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Local variables for node group configurations
locals {
  # Coordinator node group configuration
  coordinator_node_group = {
    name           = "coordinator"
    instance_types = [var.coordinator_instance_type]
    capacity_type  = "ON_DEMAND"
    min_size       = var.coordinator_instance_count
    max_size       = var.coordinator_instance_count
    desired_size   = var.coordinator_instance_count
    disk_size      = 50
    disk_type      = "gp3"
    subnet_ids     = [module.vpc.private_subnets[0]]  # Use only first AZ subnet

    labels = {
      "fluss-component" = "coordinator"
      "node-type"       = "coordinator"
      workload          = "fluss"
      service           = "coordinator"
    }

    taints = [
      {
        key    = "fluss-component"
        value  = "coordinator"
        effect = "NO_SCHEDULE"
      }
    ]

    tags = {
      Name        = "${var.eks_cluster_name}-coordinator"
      Component   = "coordinator"
      Service     = "fluss"
      Project     = "fluss-deployment"
      Environment = var.environment
    }

    enable_monitoring = false
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  # Tablet server node group configuration
  tablet_server_node_group = {
    name           = "tablet-server"
    instance_types = [var.tablet_server_instance_type]
    capacity_type  = "ON_DEMAND"
    min_size       = var.tablet_server_instance_count
    max_size       = var.tablet_server_instance_count
    desired_size   = var.tablet_server_instance_count
    disk_size      = 100
    disk_type      = "gp3"
    subnet_ids     = [module.vpc.private_subnets[0]]  # Use only first AZ subnet

    labels = {
      "fluss-component" = "tablet-server"
      "node-type"       = "tablet-server"
      workload          = "fluss"
      service           = "tablet-server"
    }

    taints = []

    tags = {
      Name        = "${var.eks_cluster_name}-tablet-server"
      Component   = "tablet-server"
      Service     = "fluss"
      Project     = "fluss-deployment"
      Environment = var.environment
    }

    enable_monitoring = false
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  # Flink JobManager node group configuration
  flink_jobmanager_node_group = {
    name           = "flink-jobmanager"
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
    min_size       = 1
    max_size       = 1
    desired_size   = 1
    disk_size      = 50
    disk_type      = "gp3"
    subnet_ids     = [module.vpc.private_subnets[0]]  # Use only first AZ subnet

    labels = {
      "flink-component" = "jobmanager"
      "node-type"       = "flink-jobmanager"
      workload          = "flink"
      service           = "flink-jobmanager"
    }

    taints = [
      {
        key    = "flink-component"
        value  = "jobmanager"
        effect = "NO_SCHEDULE"
      }
    ]

    tags = {
      Name        = "${var.eks_cluster_name}-flink-jobmanager"
      Component   = "flink-jobmanager"
      Service     = "flink"
      Project     = "fluss-deployment"
      Environment = var.environment
    }

    enable_monitoring = false
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }

  # Flink TaskManager node group configuration (2 nodes)
  flink_taskmanager_node_group = {
    name           = "flink-taskmanager"
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
    min_size       = 2
    max_size       = 2
    desired_size   = 2
    disk_size      = 100
    disk_type      = "gp3"
    subnet_ids     = [module.vpc.private_subnets[0]]  # Use only first AZ subnet

    labels = {
      "flink-component" = "taskmanager"
      "node-type"       = "flink-taskmanager"
      workload          = "flink"
      service           = "flink-taskmanager"
    }

    taints = [
      {
        key    = "flink-component"
        value  = "taskmanager"
        effect = "NO_SCHEDULE"
      }
    ]

    tags = {
      Name        = "${var.eks_cluster_name}-flink-taskmanager"
      Component   = "flink-taskmanager"
      Service     = "flink"
      Project     = "fluss-deployment"
      Environment = var.environment
    }

    enable_monitoring = false
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }
}

# EKS Module - Properly handles node joining automatically
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.eks_cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets  # EKS cluster needs 2 AZs, but node groups will use only first AZ

  # Cluster endpoint access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Enable IRSA (IAM Roles for Service Accounts) - Required for EBS CSI driver
  enable_irsa = true

  # Cluster addons - Core addons only (EBS CSI will be installed separately)
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # Enable cluster logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # EKS Managed Node Groups - Automatically handles aws-auth ConfigMap
  eks_managed_node_groups = {
    coordinator = local.coordinator_node_group
    tablet_server = local.tablet_server_node_group
    flink_jobmanager = local.flink_jobmanager_node_group
    flink_taskmanager = local.flink_taskmanager_node_group
  }

  # aws-auth configmap - Managed automatically by the module
  manage_aws_auth_configmap = true

  tags = {
    Name        = var.eks_cluster_name
    Project     = "fluss-deployment"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# EBS CSI Driver IRSA (if enabled)
# Created AFTER EKS module to get OIDC provider ARN
module "ebs_csi_irsa" {
  count = var.install_ebs_csi_driver ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.eks_cluster_name}-ebs-csi-driver"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = {
    Name        = "${var.eks_cluster_name}-ebs-csi-driver"
    Project     = "fluss-deployment"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  depends_on = [module.eks]  # Must wait for OIDC provider
}

# Install EBS CSI driver addon separately (after IRSA role is created)
resource "aws_eks_addon" "ebs_csi_driver" {
  count = var.install_ebs_csi_driver ? 1 : 0

  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa[0].iam_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update  = "OVERWRITE"

  tags = {
    Name        = "${var.eks_cluster_name}-ebs-csi-driver"
    Project     = "fluss-deployment"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  depends_on = [
    module.ebs_csi_irsa[0],
    module.eks
  ]

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

