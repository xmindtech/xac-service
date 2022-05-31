provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

###############################################################################
# create namespace
resource "kubernetes_namespace" "airflow" {
  metadata {
    labels = {
      mylabel = "xac-airflow"
    }

    name = "airflow"
  }
}
###############################################################################
# access points: airflow - AIRFLOW_HOME
resource "aws_efs_access_point" "airflow_home" {
  file_system_id = aws_efs_file_system.efs.id
  posix_user {
    uid = 50000
    gid = 0
  }
  root_directory {
    path = "/opt/airflow"
    creation_info {
      owner_uid = 50000
      owner_gid = 0
      permissions = 770
    }
  }
  tags = local.tags
}
###############################################################################
# access points: dags
resource "aws_efs_access_point" "airflow_dags" {
  file_system_id = aws_efs_file_system.efs.id
  posix_user {
    uid = 50000
    gid = 0
  }
  root_directory {
    path = "/opt/airflow/dags"
    creation_info {
      owner_uid = 50000
      owner_gid = 0
      permissions = 770
    }
  }
  tags = local.tags
}

###############################################################################
# access points: logs - airflow logs
resource "aws_efs_access_point" "airflow_logs" {
  file_system_id = aws_efs_file_system.efs.id
  posix_user {
    uid = 50000
    gid = 0
  }
  root_directory {
    path = "/opt/airflow/logs"
    creation_info {
      owner_uid = 50000
      owner_gid = 0
      permissions = 770
    }
  }
  tags = local.tags
}

###############################################################################
# access points: input source for evidences
resource "aws_efs_access_point" "xac_evidence" {
  file_system_id = aws_efs_file_system.efs.id
  posix_user {
    uid = 0
    gid = 0
  }
  root_directory {
    path = "/case-evidence"
    creation_info {
      owner_uid = 0
      owner_gid = 0
      permissions = 770
    }
  }
  tags = local.tags
}

###############################################################################
# access points: input source for evidences
resource "aws_efs_access_point" "xac_analysis" {
  file_system_id = aws_efs_file_system.efs.id
  posix_user {
    uid = 0
    gid = 0
  }
  root_directory {
    path = "/case-analysis"
    creation_info {
      owner_uid = 0
      owner_gid = 0
      permissions = 770
    }
  }
  tags = local.tags
}

###############################################################################
# create storage class
#
resource "kubectl_manifest" "storage_class" {
  depends_on = [helm_release.kubernetes_efs_csi_driver, kubernetes_namespace.airflow]
  yaml_body  = <<YAML
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-sc-static
  namespace: airflow
provisioner: efs.csi.aws.com
mountOptions:
  - tls
parameters:
  provisioningMode: efs-ap
  fileSystemId: ${aws_efs_file_system.efs.id}
YAML
}

###############################################################################
# create persistent volume - airflow
resource "kubectl_manifest" "persistent_volume_airflow" {
  depends_on = [kubectl_manifest.storage_class, aws_efs_access_point.airflow_home]
  yaml_body  = <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-pv-static-airflow
  namespace: airflow
  labels:
    airflow-path: opt-airflow
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc-static
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${aws_efs_file_system.efs.id}::${aws_efs_access_point.airflow_home.id}
    volumeAttributes:
      encryptInTransit: "true"
YAML
}


###############################################################################
# create persistent volume - airflow logs
resource "kubectl_manifest" "persistent_volume_logs" {
  depends_on = [kubectl_manifest.storage_class, aws_efs_access_point.airflow_logs]
  yaml_body  = <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-pv-static-logs
  namespace: airflow
  labels:
    airflow-path: opt-airflow-logs
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc-static
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${aws_efs_file_system.efs.id}::${aws_efs_access_point.airflow_logs.id}
    volumeAttributes:
      encryptInTransit: "true"
YAML
}


###############################################################################
# create persistent volume - evidence in

resource "kubectl_manifest" "pv_xac_evidence" {
  depends_on = [kubectl_manifest.storage_class, aws_efs_access_point.xac_evidence]
  yaml_body  = <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-pv-static-evidence
  namespace: airflow
  labels:
    airflow-path: xac-case-evidence
spec:
  capacity:
    storage: 100Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc-static
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${aws_efs_file_system.efs.id}::${aws_efs_access_point.xac_evidence.id}
    volumeAttributes:
      encryptInTransit: "true"
YAML
}

###############################################################################
# create persistent volume - results out

resource "kubectl_manifest" "pv_xac_analysis" {
  depends_on = [kubectl_manifest.storage_class, aws_efs_access_point.xac_analysis]
  yaml_body  = <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-pv-static-analysis
  namespace: airflow
  labels:
    airflow-path: xac-case-analysis
spec:
  capacity:
    storage: 100Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc-static
  csi:
    driver: efs.csi.aws.com
    volumeHandle: ${aws_efs_file_system.efs.id}::${aws_efs_access_point.xac_analysis.id}
    volumeAttributes:
      encryptInTransit: "true"
YAML
}

###############################################################################
# create persistent volume claims
resource "kubectl_manifest" "persistent_volume_claim_airflow" {
  depends_on = [kubectl_manifest.persistent_volume_airflow]
  yaml_body  = <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-claim-airflow
  namespace: airflow
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc-static
  resources:
    requests:
      storage: 10Gi
  selector:
    matchLabels:
      airflow-path: opt-airflow
YAML
}

resource "kubectl_manifest" "persistent_volume_claim_logs" {
  depends_on = [kubectl_manifest.persistent_volume_logs]
  yaml_body  = <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-claim-logs
  namespace: airflow
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc-static
  resources:
    requests:
      storage: 10Gi
  selector:
    matchLabels:
      airflow-path: opt-airflow-logs
YAML
}

resource "kubectl_manifest" "pvc_xac_evidence" {
  depends_on = [kubectl_manifest.pv_xac_evidence]
  yaml_body  = <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-claim-evidence
  namespace: airflow
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc-static
  resources:
    requests:
      storage: 100Gi
  selector:
    matchLabels:
      airflow-path: xac-case-evidence
YAML
}


resource "kubectl_manifest" "pvc_xac_analysis" {
  depends_on = [kubectl_manifest.pv_xac_analysis]
  yaml_body  = <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-claim-analysis
  namespace: airflow
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc-static
  resources:
    requests:
      storage: 100Gi
  selector:
    matchLabels:
      airflow-path: xac-case-analysis
YAML
}

###############################################################################
# airflow configmap
resource "kubernetes_config_map" "airflow_variables" {
  metadata {
    name = "airflow-variables"
    namespace = "airflow"
  }

  data = {
    AIRFLOW_VAR_S3_BUCKET = "xac-evidence-test",
    AIRFLOW_ECR_REPO = "${aws_ecr_repository.xac_repository.name}"
  }
}

###############################################################################
# airflow secrets - db password

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_id" "fernet_key" {
  byte_length = 16
}

#data "external" "fernet_key" {
#  program = ["bash", "${path.root}/scripts/generate-fernet-key.py"]
#} 

resource "kubernetes_secret" "airflow_webserver_secret" {
  metadata {
    name = "xac-webserver-secret"
    namespace = "airflow"
  }
  data = {
    "webserver-secret-key" = random_password.password.result
  }
  type = "Opaque"
}

resource "kubernetes_secret" "airflow_fernet_key" {
  metadata {
    name = "xac-fernet-key"
    namespace = "airflow"
  }
  data = {
    "fernet-key" = random_id.fernet_key.b64_std
  }
  type = "Opaque"
}