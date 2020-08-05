-- Statements to initialize environment

-- PostGIS is required: some DB features are as in GIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- Create roles

DROP ROLE IF EXISTS radar_data_provider;
CREATE ROLE radar_data_provider;

DROP ROLE IF EXISTS viewer;
CREATE ROLE viewer;

DROP ROLE IF EXISTS missile_launcher;
CREATE ROLE missile_launcher IN ROLE radar_data_provider, viewer;
