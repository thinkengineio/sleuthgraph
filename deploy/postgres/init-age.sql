-- Runs once on Postgres container first start (mounted to /docker-entrypoint-initdb.d/)
-- Installs Apache AGE extension which gives us Cypher queries over PostgreSQL.

CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- Main investigation graph (one graph for all cases for MVP;
-- per-case graphs can be a v1.1 optimization if needed).
SELECT create_graph('sleuthgraph');
