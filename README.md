
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Connect to K8s](#connect-to-k8s)
- [Locally expose Apache Airflow](#locally-expose-apache-airflow)
- [Add your workflows/dags](#add-your-workflowsdags)


# eXtendable Automation for Cloud <!-- omit in toc -->
This is a an initial release of a prototype service to support Cloud Security workflows.  
In SOAR platforms, a key function is the automation of the tasks, and orchestration among them., while covering for multiple types of environment, tools and connectors.

A popular platform for data science projects, that was proven yet and again for heavy workloads and with a rich collection of connectors is [Apache Airflow](https://airflow.apache.org/).

Another very popular platform for running containerized workloads and services is, well, Kubernetes :-)  
So based on Apache Airflow running on Kubernetes we can enable rapid development of workflows, particularly for cloud security, in any environment - AWS, Azure, GCP, PKS, etc. 

The associated playbooks (DAGs and notebooks) are in a separate project, [xac-playbooks](https://github.com/xmindtech/xac-playbooks).

## Prerequisites
1 - IAM role - with enough rights to create the needed resources.
You could also temporarily assume a more privileged role, create them, and revert back.
Note that the EKS cluster aws-auth ConfigMap will have the access rights set up for the user/role you used to create them.

2 - tooling - subsequent commands will require:
* terraform
* kubectl
* helm
* aws-iam-authenticator
* eksctl
  
You may use the scripts under `setup/` to install them.
  
## Installation
For simpler command syntax, just set `AWS_PROFILE` and `AWS_REGION` to declutter command lines.

To create the infrastructure:
```bash
$ terraform init
$ terraform plan
$ terraform apply
```

The terrafrom code will create:
* A VPC with public/private subnets, an Internet Gateway and a NAT to allow private subnets to connect to internet;
* An EKS cluster with 4 nodes, with managed and unmanaged nodegroups, one being spot allocated;
* An EFS storage with several access points, and the necessary EKS driver to use it;

Then, install Apache Airflow using the official Helm chart:
```bash
helm install  xac-airflow  apache-airflow/airflow   --namespace airflow --version "1.6.0"   --debug --timeout 10m0s  --values ./airflow/custom-values-official.yaml
```
Take note of the default credentials displayed at the end of installation.

## Connect to K8s
To connect to the cluster, update kubeconfig:
```bash
aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name)
kubectl config get-contexts
kubectl -n airflow get svc
```

## Locally expose Apache Airflow
Do not expose Airflow directly to the world before properly setting up its authentication.
For a starter, you can use it locally, forwarding the service port:
```bash
kubectl port-forward svc/airflow-webserver 8080:8080 --namespace airflow
```
Now you can browse on `http://localhost:8080`

## Add your workflows/dags
Apache Airflow has several mechanisms to deploy DAGs. 
Since we are opting for AWS EFS for easy data sharing, we will be using it to share DAGs as well.
To deploy a new DAG, copy it to your EFS:`/opt/airflow/dags/`
The volume is mounted with the webserver, scheduler and workers, therefore will be availabe.

How to copy files? Several options:  
a) using kubectl cp - find the name of the scheduler pod, and do 
```bash
kubectl -n airflow cp /path/to/dag $scheduler_pod_name:/opt/airflow/dags/
```
c) via VS Code remote - you'll need the [Kubernetes extension](https://marketplace.visualstudio.com/items?itemName=ms-kubernetes-tools.vscode-kubernetes-tools), and a simple pod to attach to (see e.g. ./util/shell.yaml) that has a volume/volume-mount definition pointing to `efs-claim-airflow` persistent volume claim. For a dev environment you could attach directly to the scheduler pod. See [this guide](https://code.visualstudio.com/docs/remote/attach-container) to see how simple it is.

c) via EFS access point or volume mount - you can just mount the EFS volume and place your dags under `/opt/airflow/dags`. 
