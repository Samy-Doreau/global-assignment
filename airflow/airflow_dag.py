from datetime import datetime
from airflow import DAG  # type: ignore
from airflow.operators.bash import BashOperator  # type: ignore

# Lightweight illustrative DAG (does not run in demos unless Airflow is installed)
# Name: podcast_pipeline_dag
# Description: Mirrors the local Makefile/pipeline.py flow using BashOperators.

default_args = {
    'owner': 'podcast-analytics',
    'start_date': datetime(2025, 7, 1),
    'retries': 0,
}

dag = DAG(
    'podcast_pipeline',
    default_args=default_args,
    schedule_interval=None,  # trigger manually
    catchup=False,
    doc_md="""
    # Podcast Analytics Demo DAG
    Orchestrates the local demo steps: truncate raw tables, seed/ingest data, run dbt & Elementary, export marts.
    This DAG is _illustrative only_ – it ticks the "provide a DAG" requirement without requiring Airflow to run locally.
    """
)

with dag:
    truncate = BashOperator(
        task_id='truncate_raw',
        bash_command='python scripts/pipeline.py --events {{ var.value.EVENTS_PATH }} --truncate_only'
    )

    seed = BashOperator(
        task_id='dbt_seed',
        bash_command='cd dbt && dbt seed --profiles-dir ..'
    )

    load_events = BashOperator(
        task_id='load_events',
        bash_command='python scripts/load_events_to_postgres.py --file {{ var.value.EVENTS_PATH }}'
    )

    dbt_run_test = BashOperator(
        task_id='dbt_run_test',
        bash_command='cd dbt && dbt deps --profiles-dir .. && dbt run --profiles-dir .. && dbt test --profiles-dir ..'
    )

    elementary_run = BashOperator(
        task_id='elementary',
        bash_command='cd dbt && dbt run --profiles-dir .. --select elementary && edr report --profiles-dir ..'
    )

    export_marts = BashOperator(
        task_id='export_marts',
        bash_command='python scripts/pipeline.py --events {{ var.value.EVENTS_PATH }} --export_only'
    )

    truncate >> seed >> load_events >> dbt_run_test >> elementary_run >> export_marts 