from datetime import datetime, timedelta
from kubernetes.client import models as k8s

from airflow import DAG

from airflow.kubernetes.secret import Secret
from airflow.operators.bash import BashOperator
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator
from airflow.operators.dummy_operator import DummyOperator

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime.utcnow(),
    'email': ['teodor@xmindtech.lu'],
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=3),
}

dag = DAG(
    dag_id='k8s_operator',
    schedule_interval=None,
    default_args=default_args,
    description='test k8s op',
    tags=['example']
)

start = DummyOperator(task_id='start', dag=dag)

step = KubernetesPodOperator(
        namespace='airflow',
        image="public.ecr.aws/amazonlinux/amazonlinux:2022",
        cmds=["/usr/bin/python3","-c"],
        arguments=["import os, json;xcom={'key1':123};open('/airflow/xcom/return.json','w').write(json.dumps(xcom))"],
        labels={"foo": "bar"},
        name="passing-test",
        task_id="passing-task",
        do_xcom_push=True,
        is_delete_operator_pod=True,
        hostnetwork=False,
        #priority_class_name="medium",
        get_logs=True,
        dag=dag
)

stop = DummyOperator(task_id='stop', dag=dag)

start >> step >> stop