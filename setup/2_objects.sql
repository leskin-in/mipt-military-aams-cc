-- Create relations and methods

DROP SCHEMA IF EXISTS cc CASCADE;
CREATE SCHEMA cc;

GRANT USAGE ON SCHEMA cc TO radar_data_provider, viewer, missile_launcher;

SET search_path TO cc,public;


-- Tables --

-- Raw radar data
CREATE TABLE radar_data(
    coordinates GEOMETRY
        NOT NULL
        CHECK (ST_GeometryType(coordinates) = 'ST_Point'),
    source CHARACTER(32),
    captured TIMESTAMP WITHOUT TIME ZONE
        NOT NULL,
    data BYTEA
);
ALTER TABLE radar_data OWNER TO missile_launcher;
GRANT INSERT ON radar_data TO radar_data_provider;
GRANT SELECT ON radar_data TO viewer;

-- Processed radar information - airborne objects
CREATE TABLE objects(
    id SERIAL
        PRIMARY KEY,
    coordinates GEOMETRY
        CHECK (ST_GeometryType(coordinates) = 'ST_Point'),
    last_update TIMESTAMP WITHOUT TIME ZONE,
    data BYTEA,
    description VARCHAR
);
ALTER TABLE objects OWNER TO missile_launcher;
GRANT SELECT ON objects TO viewer;

-- Surface-to-air anti-aircraft missile systems
CREATE TABLE sam_systems(
    id SERIAL
        PRIMARY KEY,
    coordinates GEOMETRY
        CHECK (ST_GeometryType(coordinates) = 'ST_Point'),
    type CHARACTER(16),
    division CHARACTER(32),
    description VARCHAR
);
ALTER TABLE sam_systems OWNER TO missile_launcher;
GRANT SELECT ON sam_systems TO viewer;

-- Missiles
CREATE TABLE missiles(
    sam INTEGER
        REFERENCES sam_systems(id) ON DELETE CASCADE
        NOT NULL,
    id SERIAL
        PRIMARY KEY,
    type CHARACTER(16),
    target INTEGER
        REFERENCES objects(id) ON DELETE SET NULL
        NULL
        UNIQUE,
    launch_time TIMESTAMP WITHOUT TIME ZONE
        NULL
);
ALTER TABLE missiles OWNER TO missile_launcher;
GRANT SELECT ON missiles TO viewer;

-- Objects being defended
CREATE TABLE defended_objects(
    id SERIAL
        PRIMARY KEY,
    -- Any kind of geometry, depending on object type
    definition GEOMETRY,
    priority INTEGER
        CHECK (priority BETWEEN 1 AND 10),
    description VARCHAR
);
ALTER TABLE defended_objects OWNER TO missile_launcher;
GRANT SELECT ON defended_objects TO viewer;


-- Methods --

-- Update the list of currently known objects. In real system, this operation should be performed by an external program
CREATE FUNCTION update_objects() RETURNS void AS $$
DECLARE
    obj RECORD;
BEGIN
    FOR obj IN
        SELECT id, data, last_update
        FROM objects
    LOOP
        IF obj.last_update < (
            SELECT captured
            FROM radar_data
            WHERE data = obj.data
            ORDER BY captured DESC
            LIMIT 1
        ) THEN
            WITH current_radar_data AS (
                SELECT coordinates, captured
                FROM radar_data
                WHERE data = obj.data
                ORDER BY captured DESC
                LIMIT 1
            )
            UPDATE objects SET
                last_update = (SELECT captured FROM current_radar_data),
                coordinates = (SELECT coordinates FROM current_radar_data)
            WHERE id = obj.id;
        END IF;
    END LOOP;

    INSERT INTO objects(coordinates, last_update, data)
    SELECT DISTINCT ON (data) coordinates, captured AS last_update, data
    FROM radar_data
    WHERE data NOT IN (
        SELECT data
        FROM objects
    )
    ORDER BY data, captured DESC;
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION update_objects() OWNER TO missile_launcher;

-- Get ID of the SAM system 3D-closest to 'object'
CREATE FUNCTION nearest_sam_system(object_id INT) RETURNS INT AS $$
BEGIN
    RETURN (
        SELECT id
        FROM sam_systems
        ORDER BY ST_3DDistance(coordinates, (
            SELECT coordinates
            FROM objects
            WHERE id = object_id
        ))
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION nearest_sam_system(INT) OWNER TO viewer;

-- Get a list of object identifiers 2D-within 'radius' around 'object'
CREATE FUNCTION objects_in_range(object GEOMETRY, radius FLOAT) RETURNS SETOF INTEGER AS $$
BEGIN
    RETURN QUERY
        SELECT id
        FROM objects
        WHERE ST_DWithin(object, coordinates, radius);
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION objects_in_range(GEOMETRY, FLOAT) OWNER TO viewer;

-- Launch a missile
CREATE FUNCTION launch_missile(sam_system_id INT, target_object_id INT) RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (SELECT * FROM sam_systems WHERE id = sam_system_id) THEN
        RAISE EXCEPTION 'ЗРК с указанным идентификатором не существует';
    END IF;
    IF NOT EXISTS (SELECT * FROM objects WHERE id = target_object_id) THEN
        RAISE EXCEPTION 'Объект с указанным идентификатором не существует';
    END IF;
    IF NOT EXISTS (SELECT * FROM missiles WHERE sam = sam_system_id AND target IS NULL) THEN
        RAISE EXCEPTION 'В указанном подразделении отсутствуют ракеты';
    END IF;
    UPDATE missiles
    SET
        target = target_object_id,
        launch_time = (SELECT last_update FROM objects WHERE id = target_object_id)
    WHERE id = (
        SELECT id FROM missiles WHERE sam = sam_system_id AND target IS NULL LIMIT 1
    );
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION launch_missile(INT, INT) OWNER TO missile_launcher;

-- Protect the given 'defended_object' from all objects in the given 'radius'
CREATE FUNCTION protect(defended_object_id INT, radius FLOAT) RETURNS VOID AS $$
DECLARE
    suspicious_object_id RECORD;
BEGIN
    IF NOT EXISTS (SELECT * FROM defended_objects WHERE id = defended_object_id) THEN
        RAISE EXCEPTION 'Отсутствует обороняемый объект с заданным идентификатором';
    END IF;

    FOR suspicious_object_id IN
        SELECT DISTINCT *
        FROM objects_in_range((SELECT definition FROM defended_objects WHERE id = defended_object_id), radius) AS id
        WHERE id NOT IN (
            SELECT target
            FROM missiles
            WHERE target IS NOT NULL
        )
    LOOP
        PERFORM launch_missile(
            nearest_sam_system(suspicious_object_id.id),
            suspicious_object_id.id
        );
        RAISE NOTICE 'Запущена ЗУР. Цель - объект %', suspicious_object_id.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION protect(INT, FLOAT) OWNER TO missile_launcher;


-- Views --

-- Objects and their radar data
CREATE VIEW objects_with_radar_data AS
    SELECT
        o.id AS id, ST_AsText(o.coordinates) AS coordinates, o.last_update AS last_update,
        ST_AsText(r.coordinates) AS radar_data_coordinates, r.captured AS radar_data_captured, r.source AS radar_data_source
    FROM objects o LEFT JOIN radar_data r on o.data = r.data
    ORDER BY id, radar_data_captured;
ALTER VIEW objects_with_radar_data OWNER TO missile_launcher;
GRANT SELECT ON objects_with_radar_data TO viewer;

-- Objects close to defended objects: 2D-within a hardcoded radius (~150km)
CREATE VIEW objects_near_defended_objects AS
    WITH suspicious_list AS (
        SELECT id, definition, objects_in_range(definition, 1.5) AS objid
        FROM defended_objects
    )
    SELECT id AS defended_object_id, objid AS object_id, ST_Distance(definition, (SELECT coordinates FROM objects WHERE id = objid)) AS distance
    FROM suspicious_list
    ORDER BY defended_object_id, distance, object_id;
ALTER VIEW objects_near_defended_objects OWNER TO missile_launcher;
GRANT SELECT ON objects_near_defended_objects TO viewer;

-- Objects close to sam systems: 2D-within a hardcoded radius (~150km)
CREATE VIEW objects_near_sam_systems AS
    WITH suspicious_list AS (
        SELECT id, coordinates, objects_in_range(coordinates, 1.5) AS objid
        FROM sam_systems
    )
    SELECT id AS sam_system_id, ST_AsText(coordinates) AS sam_system_coordinates, objid AS object_id, ST_Distance(coordinates, (SELECT coordinates FROM objects WHERE id = objid)) AS distance
    FROM suspicious_list
    ORDER BY sam_system_id, distance, object_id;
ALTER VIEW objects_near_sam_systems OWNER TO missile_launcher;
GRANT SELECT ON objects_near_sam_systems TO viewer;

-- Launched missiles and their targets
CREATE VIEW launched_missiles AS
    SELECT
        m.id AS id, m.type AS type,
        ST_AsText(s.coordinates) AS launch_coordinates, m.launch_time AS launch_time, o.id AS target_object_id, ST_AsText(o.coordinates) AS target_coordinates_current
    FROM missiles m
        JOIN sam_systems s ON m.sam = s.id
        JOIN objects o on m.target = o.id
    ORDER BY launch_time;
ALTER VIEW launched_missiles OWNER TO missile_launcher;
GRANT SELECT ON launched_missiles TO viewer;


-- Triggers --

-- A trigger helper function
CREATE FUNCTION radar_data_process_trigger_fn() RETURNS trigger AS $$
BEGIN
    PERFORM update_objects();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;
-- Automatically process radar data
CREATE TRIGGER radar_data_process_trigger
AFTER INSERT ON radar_data
FOR EACH STATEMENT
EXECUTE PROCEDURE radar_data_process_trigger_fn();

-- A helper function for the following trigger
CREATE FUNCTION launch_missiles_trigger_fn() RETURNS trigger AS $$
BEGIN
    PERFORM protect(id, 0.3)
    FROM defended_objects;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;
-- Automatically launch missiles
CREATE TRIGGER launch_missiles_trigger
AFTER INSERT OR UPDATE ON objects
FOR EACH STATEMENT
EXECUTE PROCEDURE launch_missiles_trigger_fn();
