# Expected results — Fabric-as-Code walkthrough

Use this checklist after deployment. It describes what operators should see
without publishing tenant-, subscription-, workspace-, user-, or resource-
specific screenshots.

Each section explains **what you're looking at**, **what it does**, and
**how it was created** by the repo.

---

## 1. Fabric — workspace contents

**Expected result** — the CI/CD workspace contains the selected profile's
Terraform-managed items. The `all` profile includes the item types below.

**What each item does**
- **`lh_demo` (Lakehouse)** — OneLake-backed store for files **and** Delta
  tables. Ideal for raw/bronze data and Spark workloads.
- **`lh_demo` (SQL analytics endpoint)** — auto-created with the Lakehouse;
  a **read-only T-SQL** surface over the Delta tables (great for BI tools).
- **`nb_demo_load` (Notebook)** — Spark/PySpark compute that transforms and
  loads data.
- **`pl_demo_ingest` (Pipeline)** — Data Factory-style orchestrator that runs
  the other items on a schedule or trigger.
- **`wh_demo` (Warehouse)** — full read/write T-SQL engine (tables, views,
  **stored procedures**, transactions).
- **`env_demo_spark` (Environment)** — reusable Spark runtime configuration.
- **`eh_demo_events` (Eventhouse)** — real-time analytics container for event
  data and KQL databases.
- **`kqldb_demo_events` (KQL Database)** — writable real-time database attached
  to the Eventhouse.
- **`vl_demo_config` (Variable Library)** — shared deployment configuration.
- **`mlexp_demo_forecast` (ML Experiment)** — tracks machine-learning runs.

**How it was created** — `03-create-workspace` (POST `/v1/workspaces`),
`04-assign-capacity`, then `05-deploy-items` creates the nine items via the
Fabric REST API. Owner is the capacity admin from `.env`.

---

## 2. Fabric — Lakehouse with loaded data

**Expected result** — the `orders_bronze` managed Delta table contains five
sample rows, and Fabric reports that the SQL analytics endpoint was created.

**What it does** — stores the demo dataset as Delta (ACID, versioned,
Spark- and SQL-queryable). This is the "bronze" landing layer of a medallion
architecture.

**How it was created** — the notebook ran `df.write.format('delta')
.saveAsTable('orders_bronze')`. The notebook was orchestrated by the pipeline
(slides 4–5), proving the chain works end-to-end.

---

## 3. Fabric — Notebook

**Expected result** — the deployed Notebook opens in the Fabric editor and uses
the canonical Python source from the repository.

**What it does** — runs the canonical Python source authored through the Git workspace.

**How it was created** — Terraform and `05-deploy-items` both read
[`fabric-git/nb_git_authoring_demo.Notebook/notebook-content.py`](../fabric-git/nb_git_authoring_demo.Notebook/notebook-content.py), the same file synchronized by Fabric Git.

---

## 4. Fabric — Data Pipeline (design)

**Expected result** — the pipeline canvas shows a **Wait** activity feeding a
**Notebook** activity through a success dependency.

**What it does** — orchestration. `Wait_BeforeNotebook` is a simple delay; on
success it runs `Run_Notebook`, which executes the canonical notebook. In a
real project you'd chain Copy activities, stored-procedure calls, and
conditional logic here.

**How it was created** — Terraform and `05-deploy-items` read
[`fabric-git/pl_git_authoring_demo.DataPipeline/pipeline-content.json`](../fabric-git/pl_git_authoring_demo.DataPipeline/pipeline-content.json). The source Notebook logical ID and neutral workspace ID are rendered to target runtime IDs in memory.

---

## 5. Fabric — Data Pipeline run

**Expected result** — the pipeline run history contains a **Succeeded** run.

**What it does** — confirms the Wait → Notebook orchestration completed.

**How it was created** — triggered via the Fabric Jobs API
(`POST /items/{id}/jobs/instances?jobType=Pipeline`); you can also click **Run**
in the canvas or schedule it.

---

## 6. Azure — Fabric capacity

**Expected result** — the `Microsoft.Fabric/capacities` resource reports
**Status: Active** and the configured F-SKU.

**What it does** — provides the **compute** that every Fabric item in the
workspace runs on. The SKU (F2…F2048) sets capacity units; F64+ unlocks Copilot
and Power BI features. It bills **per hour while active** — **Pause** it to stop
compute charges.

**How it was created** — `02-provision-capacity` deploys
[`infra/capacity.bicep`](../infra/capacity.bicep) with `az deployment group
create`. SKU and admins come from `.env`.
