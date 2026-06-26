# Screenshots — Fabric-as-Code walkthrough

A visual tour of the environment stood up by this repository, captured from a
real end-to-end deployment (a small **F-SKU** capacity in a single resource
group). Tenant- and subscription-specific details have been kept out of frame.

Each section explains **what you're looking at**, **what it does**, and
**how it was created** by the repo.

---

## 1. Fabric — workspace contents

![Fabric workspace item list](./screenshots/01-workspace-list.png)

**What you're looking at** — the `Fabric-as-Code Demo` workspace listing every
item the automation created.

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

**How it was created** — `03-create-workspace` (POST `/v1/workspaces`),
`04-assign-capacity`, then `05-deploy-items` creates the four items via the
Fabric REST API. Owner is the capacity admin from `.env`.

---

## 2. Fabric — Lakehouse with loaded data

![Lakehouse orders_bronze table](./screenshots/02-lakehouse-table.png)

**What you're looking at** — the `orders_bronze` **managed Delta table** (5
rows) inside the Lakehouse, plus the banner confirming the SQL analytics
endpoint was created.

**What it does** — stores the demo dataset as Delta (ACID, versioned,
Spark- and SQL-queryable). This is the "bronze" landing layer of a medallion
architecture.

**How it was created** — the notebook ran `df.write.format('delta')
.saveAsTable('orders_bronze')`. The notebook was orchestrated by the pipeline
(slides 4–5), proving the chain works end-to-end.

---

## 3. Fabric — Notebook

![Notebook](./screenshots/03-notebook.png)

**What you're looking at** — `nb_demo_load` open in the Fabric notebook editor
with the **PySpark (Python)** kernel and the Lakehouse attached (left Explorer).

**What it does**
- Cell 1 builds a 5-row Spark DataFrame (the demo orders).
- Cell 2 writes it to the **attached Lakehouse** as the Delta table
  `orders_bronze`.

**How it was created** — `05-deploy-items` POSTs the notebook from
[`fabric-items/notebooks/notebook-content.ipynb`](../fabric-items/notebooks/notebook-content.ipynb).
The deploy script injects the Lakehouse binding into the notebook metadata
(templated `__LAKEHOUSE_ID__` / `__WORKSPACE_ID__` tokens) so `saveAsTable`
knows where to write.

---

## 4. Fabric — Data Pipeline (design)

![Pipeline canvas](./screenshots/04-pipeline-canvas.png)

**What you're looking at** — the pipeline canvas: a **Wait** activity feeding a
**Notebook** activity via a success (green) dependency.

**What it does** — orchestration. `Wait_BeforeLoad` is a simple delay; on
success it runs `Run_Load_Notebook`, which executes the load notebook. In a
real project you'd chain Copy activities, stored-procedure calls, and
conditional logic here.

**How it was created** — `05-deploy-items` POSTs the pipeline from the
templated
[`fabric-items/pipelines/pipeline-content.json`](../fabric-items/pipelines/pipeline-content.json);
the `__NOTEBOOK_ID__` / `__WORKSPACE_ID__` tokens are replaced with real GUIDs
at deploy time, so the activity points at the right notebook.

---

## 5. Fabric — Data Pipeline run

![Pipeline run history](./screenshots/05-pipeline-run.png)

**What you're looking at** — the pipeline's **run history** with a **Succeeded**
run.

**What it does** — confirms the orchestration executed: Wait → Notebook → Delta
write all completed. This is the run that populated `orders_bronze` (slide 2).

**How it was created** — triggered via the Fabric Jobs API
(`POST /items/{id}/jobs/instances?jobType=Pipeline`); you can also click **Run**
in the canvas or schedule it.

---

## 6. Azure — Fabric capacity

![Fabric capacity in the Azure portal](./screenshots/06-azure-capacity.png)

**What you're looking at** — the `Microsoft.Fabric/capacities` resource in the
Azure portal: **Status: Active**, **SKU: F2**.

**What it does** — provides the **compute** that every Fabric item in the
workspace runs on. The SKU (F2…F2048) sets capacity units; F64+ unlocks Copilot
and Power BI features. It bills **per hour while active** — **Pause** it to stop
compute charges.

**How it was created** — `02-provision-capacity` deploys
[`infra/capacity.bicep`](../infra/capacity.bicep) with `az deployment group
create`. SKU and admins come from `.env`.
