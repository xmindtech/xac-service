# based on https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html

resource "aws_efs_file_system" "efs" {
   creation_token = "efs"
   performance_mode = "generalPurpose"
   throughput_mode = "bursting"
   encrypted = "true"
 tags = {
     Name = var.efs_name
     Owner = var.owner_id
     Project = var.deployment_name
   }
 }


# EFS Mount Targets
resource "aws_efs_mount_target" "xac-airflow-efs-mt" {
   count = length(data.aws_availability_zones.available.names)
   file_system_id  = aws_efs_file_system.efs.id
   subnet_id = module.vpc.private_subnets[count.index]
   #subnet_id = element(module.vpc.private_subnets, count.index)
   security_groups = [aws_security_group.xac_airflow_efs_sg.id]
 }


# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
# EFS SG
resource "aws_security_group" "xac_airflow_efs_sg" {
   name = "xac_airflow_efs"
   description= "Allows inbound efs traffic from EKS"
   vpc_id = module.vpc.vpc_id

   ingress {
     from_port = 2049
     to_port = 2049 
     protocol = "tcp"
     #cidr_blocks = [module.vpc.vpc_cidr_block]
     # 192.168 included for development
     cidr_blocks = [module.vpc.vpc_cidr_block, "192.168.0.0/24"]
   }     
  
  # fix from https://github.com/aws-samples/aws-eks-accelerator-for-terraform/commit/e6b364d87221eb481d8e93b08bb9597c1e22bf3e
  #
   egress {
     from_port = 0
     to_port = 0
     protocol = "-1"
     #cidr_blocks = [module.vpc.vpc_cidr_block]
     # 192.168 included for development
     cidr_blocks = [module.vpc.vpc_cidr_block, "192.168.0.0/24"]
     #cidr_blocks = module.vpc.private_subnets_cidr_blocks
   }
   
   tags = local.tags
 }

###############################################################################
# Create an IAM policy and role
###############################################################################
# based on https://github.com/DNXLabs/terraform-aws-eks-efs-csi-driver/blob/master/iam.tf

data "aws_iam_policy_document" "efs_csi_driver" {
  statement {
    actions = [
      "elasticfilesystem:DescribeAccessPoints",
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets",
      "ec2:DescribeAvailabilityZones"
    ]
    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    actions = [
      "elasticfilesystem:CreateAccessPoint"
    ]
    resources = ["*"]
    effect    = "Allow"
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }

  statement {
    actions = [
      "elasticfilesystem:DeleteAccessPoint"
    ]
    resources = ["*"]
    effect    = "Allow"
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/efs.csi.aws.com/cluster"
      values   = ["true"]
    }
  }
}

# create policy
resource "aws_iam_policy" "eks_efs_driver_policy" {
  name        = "xac-efs-csi-driver-policy"
  description = "allow EKS access to EFS"
  policy = data.aws_iam_policy_document.efs_csi_driver.json
}

# create role
resource "aws_iam_role" "eks_efs_driver_role" {
  depends_on = [module.eks]
  name = "xac-efs-csi-driver-role"
  assume_role_policy = <<-EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "${module.eks.oidc_provider_arn}"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "oidc.eks.${local.region}.amazonaws.com/id/${basename(module.eks.oidc_provider_arn)}:sub": "system:serviceaccount:kube-system:aws-efs-csi-driver-sa"
           }
         }
       }
     ]
   }
   EOF
}

resource "aws_iam_policy_attachment" "eks_efs_driver_attach" {
  name       = "eks_efs_driver_attach"
  roles      = ["${aws_iam_role.eks_efs_driver_role.name}"]
  policy_arn = aws_iam_policy.eks_efs_driver_policy.arn
}


###############################################################################
# Create k8s service role - skipped as will be using HELM
###############################################################################
#resource "kubernetes_service_account" "efs_csi_sa" {
#    metadata {
#        name = "aws-efs-csi-driver-sa"
#        namespace = "kube-system"
#        annotations = {
#            "eks.amazonaws.com/role-arn" : aws_iam_role.eks_efs_driver_role.arn
#        }
#        labels = {
#            "app.kubernetes.io/name" : "aws-efs-csi-driver"
#        }
#    }
#}

###############################################################################
# Install the Amazon EFS driver
###############################################################################
# modified from https://github.com/DNXLabs/terraform-aws-eks-efs-csi-driver

resource "helm_release" "kubernetes_efs_csi_driver" {
  name       = "aws-efs-csi-driver"
  chart      = "aws-efs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  version    = "2.2.0"
  namespace  = "kube-system"

  set {
    name  = "controller.serviceAccount.create"
    value = "true" 
  }

  set {
    name  = "controller.serviceAccount.name"
    value =  "aws-efs-csi-driver-sa"
  }

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value =  aws_iam_role.eks_efs_driver_role.arn
  }

  set {
    name = "node.serviceAccount.create"
    # We're using the same service account for both the nodes and controllers,
    # and we're already creating the service account in the controller config
    # above.
    value = "false"
  }

  set {
    name  = "node.serviceAccount.name"
    value = "aws-efs-csi-driver-sa"
  }

  set {
    name  = "node.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.eks_efs_driver_role.arn
  }
}