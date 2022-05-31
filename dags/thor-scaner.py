import uuid

from datetime import datetime, timedelta
from kubernetes.client import models as k8s

from airflow import DAG
from airflow.models.param import Param

#from airflow.kubernetes.secret import Secret
#from airflow.operators.bash import BashOperator

from airflow.decorators import task
from airflow.operators.python import BranchPythonOperator
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator
from airflow.operators.dummy_operator import DummyOperator
from airflow.utils.trigger_rule import TriggerRule
from airflow.utils.edgemodifier import Label
from pprint import pprint


default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime.utcnow(),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=3),
}

scan_options = ['path', 'snapshot', 'ebs', 'bucket']

with DAG(
    dag_id='thor_scanner_priv',
    schedule_interval=None,
    catchup=False,
    default_args=default_args,
    description='thor scanner',
    tags=['thor-scanner'],
    params= {
        'evidence-type': Param('path', enum=scan_options),
        'evidence-source': Param('/case-evidence/test-case', type='string'),
        'analysis-output': Param('/case-analysis', type='string'),
    }
) as dag:
    start = DummyOperator(task_id='start')

    # [START]
    @task(task_id="show_context")
    def print_context(ds=None, **kwargs):
        pprint(kwargs)
        print(ds)
        return 'Whatever you return gets printed in the logs'
    show_context = print_context()
    start >> show_context
    # [END]

    # [START] switch
    scan_switch = BranchPythonOperator(
        task_id='scan-type',
        python_callable=lambda: 'scan-' + dag.params['evidence-type'],
    ) 
    show_context >> scan_switch
    # [END]

    
    # [START] Pod boilerplate
    pod_volumes = [
        k8s.V1Volume(
            name='case-evidence',
            persistent_volume_claim=k8s.V1PersistentVolumeClaimVolumeSource(claim_name='efs-claim-evidence'),
        ),
        k8s.V1Volume(
            name='case-analysis',
            persistent_volume_claim=k8s.V1PersistentVolumeClaimVolumeSource(claim_name='efs-claim-analysis'),
        )
    ]
    pod_volume_mounts = [
        k8s.V1VolumeMount(mount_path='/case-evidence', name='case-evidence', sub_path=None, read_only=True),  # input
        k8s.V1VolumeMount(mount_path='/case-analysis', name='case-analysis', sub_path=None, read_only=False), # output
    ]
    # [END]

    task_options = []
    # [START] scanner profiles
    scanner_job_id = "thor-scanner-" + uuid.uuid4().hex
    for option in scan_options:
        task_id = 'scan-' + option
        thor_scan = KubernetesPodOperator(
                namespace='airflow',
                name="thor-scan",
                task_id=task_id,
                volumes = pod_volumes,
                volume_mounts=pod_volume_mounts,
                full_pod_spec= k8s.V1Pod(
                    api_version="v1",
                    kind="Pod",
                    metadata=k8s.V1ObjectMeta(
                        namespace="airflow",
                        name=scanner_job_id,
                        labels={'app':'thor-scanner'},
                    ),
                    spec=k8s.V1PodSpec(
                        containers=[
                            k8s.V1Container(
                                name='thor-scanner',
                                image="REPO.dkr.ecr.REGION.amazonaws.com/xac-repository/xac:TAG",
                                command=["/dfir/run.sh", 
                                    "thor", 
                                    "--utc",
                                    "--lab",
                                    "--intense",
                                    # produce JSON file
                                    "--jsonfile",
                                    # scan all fs types (to scan on NFS)
                                    "--alldrives",
                                    # thor scanning template 
                                    "-t", "/dfir/thor/config/thor.yml",
                                    # path to scan 
                                    "--path", "/case-evidence/test-case",
                                    # virtual path maps
                                    "--virtual-map", "/case-evidence/test-case/:/",
                                    # where to put results
                                    "-e", "/case-analysis/thor-results/"+scanner_job_id,          
                                ],
                                # XXX:TODO - allocate larger resources just for the scan
                                resources=k8s.V1ResourceRequirements(
                                    requests = {
                                        "cpu": 1,
                                        "memory": "2Gi",
                                        "ephemeral-storage": "2Gi",
                                    },
                                    limits = { "cpu": 1,
                                        "memory": "2Gi",
                                        "ephemeral-storage": "2Gi",
                                    }
                                ),
                                security_context=k8s.V1SecurityContext(
                                    #allow_privilege_escalation=True,
                                    privileged=True,
                                    run_as_user=0,
                                )
                            )
                        ]
                    )
                ),
                is_delete_operator_pod=True, # (don't) delete the pod at the end
                hostnetwork=False,
                get_logs=True, # :param get_logs: get the stdout of the container as logs of the tasks.
                log_events_on_failure=True,
                do_xcom_push=False,
        )
        task_options.append(thor_scan)
    
    # [START]
    stop = DummyOperator(
            task_id='stop',
            trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS,
    )
    # [END]

    start >> show_context >> scan_switch >> task_options >> stop