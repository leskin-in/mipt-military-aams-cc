-- Set self forces

SET search_path TO cc,public;

-- Define an object to defend
INSERT INTO defended_objects(definition, priority, description) VALUES
(ST_MakePolygon('LINESTRING(55.965701 37.396973 0.0, 55.969144 37.417705 0.0, 55.964296 37.421146 0.0, 55.960001 37.401158 0.0, 55.965701 37.396973 0.0)'), 1, 'Аэропорт Шереметьево - терминалы DEF'),
('POINT(55.981180 37.413514 0.0)', 2, 'Аэропорт Шереметьево - Терминал B');

-- Define SAM systems
INSERT INTO sam_systems(coordinates, type, division, description) VALUES
('POINT(55.927525 37.519011 0.0)', '35р6', '531зрп', ''),
('POINT(55.983368 37.207748 0.0)', '35р6', '583зрп', '');

-- Define AAMs
INSERT INTO missiles(sam, type) VALUES
(1, '48н6'),
(1, '48н6'),
(1, '48н6'),
(1, '48н6'),
(1, '48н6'),
(1, '48н6'),
(1, '48н6'),
(1, '48н6'),
(1, '48н6'),
(1, '48н6'),
(1, '48н6'),
(1, '48н6'),
(2, '48н6е2'),
(2, '48н6е2'),
(2, '48н6е2'),
(2, '48н6е2'),
(2, '48н6е2'),
(2, '48н6е2'),
(2, '48н6е2'),
(2, '48н6е2'),
(2, '48н6е2'),
(2, '48н6е2'),
(2, '48н6е2'),
(2, '48н6е2');
