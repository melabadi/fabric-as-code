-- =============================================================================
-- 03-stored-procedures.sql
-- Creates demo stored procedures in the Fabric Warehouse.
-- These are deployed by 06-deploy-stored-procedures (PowerShell) / the bash
-- equivalent, which connect to the Warehouse SQL endpoint with Entra auth.
-- =============================================================================

-- Drop-and-recreate pattern keeps deployments idempotent.
IF OBJECT_ID('sales.usp_seed_orders', 'P') IS NOT NULL
    DROP PROCEDURE sales.usp_seed_orders;
GO

CREATE PROCEDURE sales.usp_seed_orders
AS
BEGIN
    -- Idempotent demo seed: clear and reload a few rows.
    DELETE FROM sales.orders;

    INSERT INTO sales.orders (order_id, customer_id, order_date, amount, status)
    VALUES
        (1, 101, '2026-01-05', 120.50, 'shipped'),
        (2, 102, '2026-01-06',  75.00, 'shipped'),
        (3, 101, '2026-01-07', 240.00, 'pending'),
        (4, 103, '2026-01-08',  18.99, 'cancelled'),
        (5, 104, '2026-01-09', 999.95, 'shipped');
END
GO

IF OBJECT_ID('sales.usp_refresh_orders_summary', 'P') IS NOT NULL
    DROP PROCEDURE sales.usp_refresh_orders_summary;
GO

CREATE PROCEDURE sales.usp_refresh_orders_summary
AS
BEGIN
    -- Rebuild the daily summary table from the orders table.
    DELETE FROM sales.orders_summary;

    INSERT INTO sales.orders_summary (summary_date, order_count, total_amount, refreshed_at_utc)
    SELECT
        order_date                AS summary_date,
        COUNT(*)                  AS order_count,
        SUM(amount)               AS total_amount,
        SYSUTCDATETIME()          AS refreshed_at_utc
    FROM sales.orders
    WHERE status <> 'cancelled'
    GROUP BY order_date;
END
GO
