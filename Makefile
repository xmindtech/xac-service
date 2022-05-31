AIRFLOW_NAME="xac-airflow"
AIRFLOW_NAMESPACE="airflow"
AIRFLOW_HELM_VERSION="1.6.0"
AWS_DEFAULT_REGION="eu-west-1"

plan:
	terraform plan -out terraform.tfstate.plan

install-infra: plan
	terraform apply -auto-approve "terraform.tfstate.plan" 

install-airflow:
	helm install $(AIRFLOW_NAME) apache-airflow/airflow  --namespace $(AIRFLOW_NAMESPACE) --version $(AIRFLOW_HELM_VERSION) \
	       	--debug --timeout 10m0s --values ./airflow/custom-values-official.yaml

all: install-infra install-airflow

ecr-ls:
	aws ecr describe-repositories |jq -r '.repositories[]|[.repositoryName, .repositoryUri]|@tsv'

ecr-login:
	aws ecr get-login-password --region $(AWS_DEFAULT_REGION) |docker login --username AWS --password-stdin \
		$(shell aws ecr describe-repositories |jq -r '.repositories[]|select(.repositoryName|contains("xac-repository"))|.repositoryUri')

efs-ls:
	aws efs describe-file-systems --output text
	aws efs describe-access-points --file-system-id $(shell aws efs describe-file-systems |jq -r '.FileSystems[]|select(.Name|contains("xac-airflow-efs"))|.FileSystemId') --output text


clean-airflow:
	helm -n airflow delete airflow || true
	kubectl delete namespace airflow || true
	kubectl delete sc/efs-sc-static pv/efs-pv-static-airflow pv/efs-pv-static-logs pv/efs-pv-static-evidence pv/efs-pv-static-analysis
