# based on https://github.com/terraform-aws-modules/terraform-aws-eks

provider "aws" {
  region = local.region
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

locals {
  name            = "${var.deployment_name}-${random_string.suffix.result}"
  #name            = var.deployment_name
  region          = var.aws_region
  cluster_version = "1.22"

  tags = {
    Project = var.deployment_name
    Owner   = var.owner_id
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }
}

provider "kubernetes" {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    args        = ["eks", "get-token", "--cluster-name", local.name]
    command     = "aws"
  }
}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

################################################################################
# EKS Module
################################################################################
# for access do 
resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.tags
}

resource "aws_security_group" "additional" {
  name_prefix = "${local.name}-additional"
  vpc_id      = module.vpc.vpc_id

  # verify you want this to ssh into nodes
  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = [
      "10.0.0.0/16",
      "172.16.0.0/12",
      "192.168.0.0/24"
    ]
  }

  tags = local.tags
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "18.21.0"

  cluster_name                    = local.name
  cluster_version                 = local.cluster_version
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  manage_aws_auth_configmap = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts = "OVERWRITE"
    }
  }
  
  #X: added
  cluster_enabled_log_types = ["api", "audit","authenticator","controllerManager","scheduler"]

  #X: added
  cluster_encryption_config = [{
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }]

  #X: Added - https://github.com/terraform-aws-modules/terraform-aws-eks/blob/v18.10.2/examples/complete/main.tf#L47
   # Extend cluster security group rules
  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

   # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
  
  # Self Managed Node Group(s)
  self_managed_node_group_defaults = {
    vpc_security_group_ids       = [aws_security_group.additional.id]
    iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  }
  
  # Self Managed Node Group(s)
  self_managed_node_groups = {
    refresh = {
      max_size     = 5
      desired_size = 1

      instance_type = var.eks_instance_type_1

      instance_refresh = {
        strategy = "Rolling"
        preferences = {
          checkpoint_delay       = 600
          checkpoint_percentages = [35, 70, 100]
          instance_warmup        = 300
          min_healthy_percentage = 50
        }
        triggers = ["tag"]
      }

      tags = { "aws-node-termination-handler/managed" = "true" }
    }

    mixed_instance = {
      use_mixed_instances_policy = true
      mixed_instances_policy = {
        instances_distribution = {
          on_demand_base_capacity                  = 0
          on_demand_percentage_above_base_capacity = 10
          spot_allocation_strategy                 = "capacity-optimized"
        }

        override = [
          {
            instance_type     = var.eks_instance_type_1
            weighted_capacity = "1"
          },
          {
            instance_type     = var.eks_instance_type_2
            weighted_capacity = "2"
          },
        ]
      }

      tags = { "aws-node-termination-handler/managed" = "true" }
    }

    spot = {
      instance_type = var.eks_instance_type_spot
      instance_market_options = {
        market_type = "spot"
      }

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle=spot'"
      
      post_bootstrap_user_data = <<-EOT
      cd /tmp
      sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
      sudo systemctl enable amazon-ssm-agent
      sudo systemctl start amazon-ssm-agent
      EOT
      
      tags                 = { "aws-node-termination-handler/managed" = "true" }
    }
  }
  
  #X: added - https://github.com/terraform-aws-modules/terraform-aws-eks/blob/v18.10.2/examples/complete/main.tf#L47
  eks_managed_node_group_defaults = {
    ami_type               = var.eks_ami_type
    instance_types         = [var.eks_instance_type_1, var.eks_instance_type_2]
    disk_size              = 50
    vpc_security_group_ids = [aws_security_group.additional.id]
    attach_cluster_primary_security_group = true
  }
  
  eks_managed_node_groups = {
    blue = {}
    green = {
      min_size     = 1
      max_size     = 10
      desired_size = 1

      instance_types = [var.eks_instance_type_1]
      capacity_type  = "SPOT"
      labels = {
        Environment = "test"
        GithubRepo  = "terraform-aws-eks"
        GithubOrg   = "terraform-aws-modules"
      }

      taints = {
        dedicated = {
          key    = "dedicated"
          value  = "gpuGroup"
          effect = "NO_SCHEDULE"
        }
      }

      update_config = {
        max_unavailable_percentage = 50 # or set `max_unavailable`
      }

      tags = local.tags
    }
  }

  
  

  # aws_auth_roles = []
  aws_auth_roles = [
    {
      rolearn  = "arn:aws:iam::${var.deployment_account}:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS"
      username = "AWSServiceRoleForAmazonEKS"
      groups   = ["system:masters"]
    }
  ]
  # aws_auth_users = []
  # aws_auth_accounts = []

  #  List of CIDR blocks which can access the Amazon EKS public API server endpoint
  cluster_endpoint_public_access_cidrs = var.eks_public_access_cidrs

  tags = local.tags
}

################################################################################
# aws-auth configmap
################################################################################

# data "aws_eks_cluster_auth" "this" {
#   name = module.eks.cluster_id
# }

# locals {
#   kubeconfig = yamlencode({
#     apiVersion      = "v1"
#     kind            = "Config"
#     current-context = "terraform"
#     clusters = [{
#       name = module.eks.cluster_id
#       cluster = {
#         certificate-authority-data = module.eks.cluster_certificate_authority_data
#         server                     = module.eks.cluster_endpoint
#       }
#     }]
#     contexts = [{
#       name = "terraform"
#       context = {
#         cluster = module.eks.cluster_id
#         user    = "terraform"
#       }
#     }]
#     users = [{
#       name = "terraform"
#       user = {
#         token = data.aws_eks_cluster_auth.this.token
#       }
#     }]
#   })
  
#   # we have to combine the configmap created by the eks module with the externally created node group/profile sub-modules
#   aws_auth_configmap_yaml = <<-EOT
#   ${chomp(module.eks.aws_auth_configmap_yaml)}
#       - rolearn: ${module.eks_managed_node_group.iam_role_arn}
#         username: system:node:{{EC2PrivateDNSName}}
#         groups:
#           - system:bootstrappers
#           - system:nodes
#       - rolearn: ${module.self_managed_node_group.iam_role_arn}
#         username: system:node:{{EC2PrivateDNSName}}
#         groups:
#           - system:bootstrappers
#           - system:nodes
#       - rolearn: ${module.fargate_profile.fargate_profile_pod_execution_role_arn}
#         username: system:node:{{SessionName}}
#         groups:
#           - system:bootstrappers
#           - system:nodes
#           - system:node-proxier
#   EOT
# }



################################################################################
# Supporting Resources
################################################################################
data "aws_availability_zones" "available" {}

# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.available.names
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.tags
}