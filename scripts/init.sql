-- PostgreSQL initialization script for routing table collector
-- This script sets up additional database configurations

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "inet";

-- Create indexes for better performance (these will be created by SQLAlchemy as well)
-- This is just for reference and future manual optimizations

-- Set timezone
SET timezone = 'UTC';

-- Create a read-only user for reporting
CREATE USER reporter WITH PASSWORD 'readonly';
GRANT CONNECT ON DATABASE routing_tables TO reporter;
GRANT USAGE ON SCHEMA public TO reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reporter;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO reporter;