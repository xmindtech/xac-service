
#module "aws_ebs_csi_driver" {
#  source                           = "github.com/andreswebs/terraform-aws-eks-ebs-csi-driver"
#  cluster_name                     = module.eks.cluster_id
#  cluster_oidc_provider            = module.eks.oidc_provider
#  iam_role_name                    = "ebs-csi-driver-role"
#  chart_version_aws_ebs_csi_driver = "0.9.4"
#}