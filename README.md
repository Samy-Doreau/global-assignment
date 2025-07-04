# Podcast Analytics – Local Demo

## Prerequisites

- Install Docker Desktop ≥ 4
- Python 3.10+

## Setup Python Environment

```bash
# Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

## dbt Profile Configuration

This project uses a local `profiles.yml` file to configure the connection to the Postgres database. This ensures that the project's dbt configuration does not interfere with any other dbt projects you may have on your system (e.g., in `~/.dbt/profiles.yml`).

The `Makefile` commands for running dbt are set up to use the `profiles.yml` in this project's root directory. The file contains the necessary `podcast_analytics` profile:

```yaml
# profiles.yml
podcast_analytics:
  target: local
  outputs:
    local:
      type: postgres
      host: localhost
      user: "{{ env_var('POSTGRES_USER') }}"
      password: "{{ env_var('POSTGRES_PASSWORD') }}"
      port: 5432
      dbname: "{{ env_var('POSTGRES_DB') }}"
      schema: public
      threads: 4
```

You do not need to do any manual configuration for the dbt profile if you use the provided `make` commands.

If you wish to run `dbt` commands manually, ensure you are in the `dbt/` directory and point to the profiles directory in the parent folder:

```bash
cd dbt
dbt run --profiles-dir ..
```

## Environment Setup

The `env.example` file contains these database settings:

- `POSTGRES_USER=podcast` - Database username
- `POSTGRES_PASSWORD=podcast` - Database password
- `POSTGRES_DB=podcast_analytics` - Database name

You can modify these values in your `.env` file if needed.

## 1. Spin up Postgres

Create the environment file containg the postgres connection details, then deploy the local server with docker.

```bash
cp env.example .env
make up  # or: docker compose up -d
```

**What this does:**

- `cp env.example .env` - Creates your local environment file with database credentials
- `make up` - Starts a PostgreSQL database in Docker with the settings from your `.env` file

The database will be available at `localhost:5432` with the credentials specified in the `.env` file.

## 2. Load sample events

```bash
make load-data FILE=data/event_logs.jsonl
```

## 3. Spin down Postgres

When you're done, you can stop and remove the Postgres container with:

```bash
make down
```

## Inspecting the Database

After a successful run of `make dbt`, you can manually inspect the objects created in the database.

1.  **Connect to the Postgres container:**

    ```bash
    docker exec -it podcast_pg psql -U podcast -d podcast_analytics
    ```

2.  **Inside `psql`, you can list the created objects:**

    - **List all views (the marts):**

      ```sql
      \dv
      ```

      You should see:

      - `mart_top_episodes`
      - `mart_user_session_metrics`
      - And all the intermediate/staging models, as they are also created as views by default.

    - **List all tables (seeds and raw tables):**

      ```sql
      \dt
      ```

      Or, to list views :

      ```sql
      \dv
      ```

      You should see:

      - `raw_users`
      - `raw_episodes`
      - `raw_event_files`

    - **Query a mart view:**

      ```sql
      SELECT * FROM mart_top_episodes LIMIT 10;
      ```

    - **Exit `psql`:**
      ```sql
      \q
      ```

## Troubleshooting

- If dbt cannot connect, ensure the container is healthy: `docker ps`.
- Delete the `pgdata` volume to reset Postgres: `docker compose down -v`.
- On Apple Silicon you may need to allow x86 emulation for the Postgres image.
- In case OSX security prevents the installation of Docker Desktop, follow the instructions [in this thread](https://github.com/docker/for-mac/issues/7520#issuecomment-2578291149) to resolve.
