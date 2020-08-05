-- Create self roles

DROP USER IF EXISTS petrov;
CREATE USER petrov PASSWORD 'petrov' IN ROLE missile_launcher;

DROP USER IF EXISTS sidorov;
CREATE USER sidorov PASSWORD 'sidorov' IN ROLE viewer;

DROP USER IF EXISTS radar;
CREATE USER radar PASSWORD 'radar' IN ROLE radar_data_provider;
