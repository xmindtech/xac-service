#!/bin/bash
export AIRFLOW_NAME="airflow"; export AIRFLOW_NAMESPACE="airflow"
helm repo add apache-airflow https://airflow.apache.org
helm repo update
helm install  $AIRFLOW_NAME  apache-airflow/airflow   --namespace $AIRFLOW_NAMESPACE   --create-namespace  --version "1.5.0"   --debug --timeout 10m0s  --values ../airflow/custom-values-official.yaml