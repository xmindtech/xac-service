variable "owner_id" {
  type        = string
  description = "User-id/owner for the created resources owner tag"
  default     = "xac"
}

variable "aws_region" {
  type        = string
  description = "For AWS deployment - region name"
  default     = "eu-west-1"
}

variable "deployment_name" {
  type        = string
  description = "Name to be used as prefix for resources"
  default     = "xac-airflow"
}

variable "deployment_account" {
  type        = string
  description = "AWS Account Id wehere deploying it"
  default     = "YOUR-ACCOUNT-HERE"
}

variable "eks_instance_type_1" {
  type        = string
  description = "Type of EC2 instance to use for EKS nodes mix"
  default     = "m5.large"
}

variable "eks_instance_type_2" {
  type        = string
  description = "Type of EC2 instance to use for EKS nodes mix"
  default     = "m6i.large"
}

variable "eks_instance_type_spot" {
  type        = string
  description = "Type of EC2 instance to use for EKS nodes mix - spot instances"
  default     = "m5.large"
}

variable "eks_ami_type" {
  type        = string
  description = "The id of the machine image (AMI) to use for the nodes."
  default     = "AL2_x86_64"
}

variable eks_public_access_cidrs {
  type        = list
  description = "List of CIDR blocks which can access the Amazon EKS public API server endpoint"
  default     = ["0.0.0.0/0"]
}

variable "efs_name" {
  type        = string
  description = "EFS service name"
  default     = "xac-airflow-efs"
}


