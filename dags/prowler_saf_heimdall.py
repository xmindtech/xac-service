import random

import pendulum

from airflow import DAG
from airflow.models.param import Param

from airflow.operators.empty import EmptyOperator
from airflow.operators.python import BranchPythonOperator
from airflow.utils.edgemodifier import Label
from airflow.utils.trigger_rule import TriggerRule

with DAG(
    dag_id='prowler_saf_heimdall',
    start_date=pendulum.datetime(2021, 1, 1, tz="UTC"),
    catchup=False,
    schedule_interval="@daily",
    tags=['prowler', 'saf','heimdall'],
    params= {
        'target': Param('', type='string'),
        'regions': Param('eu-west-1,eu-west-2,eu-west-3,eu-central-1,eu-north-1,eu-south-1', type='string'),
        'output': Param('/case-analysis', type='string'),
    }
) as dag:

    check_params = EmptyOperator(
        task_id='check_params',
    )

    multi_region = EmptyOperator(
        task_id='multi_region',
    )

    single_region = EmptyOperator(
        task_id='single_region',
    )
    
    join = EmptyOperator(
        task_id='join',
        trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS,
    )

    regions = dag.params['regions'].split(',')  
    options = ['single_region', 'multi_region']

    run_strategy = BranchPythonOperator(
        task_id='run_strategy',
        python_callable=lambda: 'multi_region' if len(regions) > 1 else 'single_region' ,
    )

    check_params >> run_strategy >> [multi_region, single_region] >> join

    # multi region
    join_multi_region = EmptyOperator(
        task_id='join_multi_region',
        trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS,
    )

    for region in regions:
        # todo - validate region
        if region == '':
            continue
        t = EmptyOperator(
            task_id='prowler_scan_' + region,
        )

        # Label is optional here, but it can help identify more complex branches
        multi_region >> Label(region) >> t >> join_multi_region >> join

    convert_to_hdf = EmptyOperator(
        task_id='convert_to_hdf'
    )

    deploy_to_heimdall = EmptyOperator(
        task_id='deploy_to_heimdall'
    )
    
    join >> convert_to_hdf >> deploy_to_heimdall