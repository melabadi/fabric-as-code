# Screenshots — Fabric-as-Code walkthrough

A visual tour of the environment stood up by this repository, captured from a
real end-to-end deployment (a small **F-SKU** capacity in a single resource
group). Tenant- and subscription-specific details have been kept out of frame.

---

## 1. Fabric — workspace contents

The workspace with every item created via the Fabric REST API: Lakehouse, its
SQL analytics endpoint, Warehouse, Notebook, and the Data Pipeline.

![Fabric workspace item list](./screenshots/01-workspace-list.png)

## 2. Fabric — Lakehouse with loaded data

The `orders_bronze` managed Delta table written by the notebook run (5 rows).

![Lakehouse orders_bronze table](./screenshots/02-lakehouse-table.png)

## 3. Fabric — Notebook

`nb_demo_load`, bound to the Lakehouse, writing the demo dataset with PySpark.

![Notebook](./screenshots/03-notebook.png)

## 4. Fabric — Data Pipeline (design)

`pl_demo_ingest`: a **Wait** activity followed by a **Notebook** activity.

![Pipeline canvas](./screenshots/04-pipeline-canvas.png)

## 5. Fabric — Data Pipeline run

The pipeline run history showing a **Succeeded** run.

![Pipeline run history](./screenshots/05-pipeline-run.png)

## 6. Azure — Fabric capacity

The billable compute (`Microsoft.Fabric/capacities`) created by
[`infra/capacity.bicep`](../infra/capacity.bicep): **Status: Active**, **F2 SKU**.

![Fabric capacity in the Azure portal](./screenshots/06-azure-capacity.png)
