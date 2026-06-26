-- =============================================================================
-- 01-create-schema.sql
-- Runs against the Fabric Warehouse SQL endpoint.
-- Creates the schema used by the demo objects.
-- =============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'sales')
    EXEC('CREATE SCHEMA sales');
GO
