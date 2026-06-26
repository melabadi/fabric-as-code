-- =============================================================================
-- 02-create-tables.sql
-- Creates demo tables in the Fabric Warehouse.
-- Note: Fabric Warehouse does not support PRIMARY KEY/IDENTITY the same way as
-- SQL Server; constraints are limited. Keep DDL warehouse-compatible.
-- =============================================================================

IF OBJECT_ID('sales.orders', 'U') IS NULL
BEGIN
    CREATE TABLE sales.orders
    (
        order_id      INT          NOT NULL,
        customer_id   INT          NOT NULL,
        order_date    DATE         NOT NULL,
        amount        DECIMAL(18,2) NOT NULL,
        status        VARCHAR(20)  NOT NULL
    );
END
GO

IF OBJECT_ID('sales.orders_summary', 'U') IS NULL
BEGIN
    CREATE TABLE sales.orders_summary
    (
        summary_date     DATE          NOT NULL,
        order_count      INT           NOT NULL,
        total_amount     DECIMAL(18,2) NOT NULL,
        refreshed_at_utc DATETIME2(0)  NOT NULL
    );
END
GO
