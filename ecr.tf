# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository
resource "aws_ecr_repository" "xac_repository" {
  name = "xac-repository/xac"
  image_tag_mutability = "MUTABLE" # "IMMUTABLE"
  encryption_configuration {
    encryption_type = "KMS"
  }

  image_scanning_configuration {
    # whether images are scanned after being pushed to the repository
    scan_on_push = true
  }
  tags = local.tags
}

resource "aws_ecr_repository_policy" "xac_repo_policy" {
  repository = aws_ecr_repository.xac_repository.name
  policy     = <<EOF
  {
    "Version": "2008-10-17",
    "Statement": [
      {
        "Sid": "adds full ecr access to the repository",
        "Effect": "Allow",
        "Principal": {
            "AWS": "${data.aws_caller_identity.current.account_id}"
        },
        "Action": [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetLifecyclePolicy",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
      }
    ]
  }
  EOF
}

/*
locals {
  dockerconfigjson = {
    "${aws_ecr_repository.xac_repository.repository_url}" = {
      username = "AWS"       
      password = "test"      
    }
  }
}

resource "kubernetes_secret" "xac_ecr_login" {
  metadata {
    name = "docker-registry"
    namespace = "airflow"
  }
  data = {
    ".dockerconfigjson" = jsonencode(local.dockerconfigjson)
  }
  type = "kubernetes.io/dockerconfigjson"
}
*/