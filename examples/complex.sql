-- Load with:  sqlite3 ui.db < examples/complex.sql
-- Assumes the schema from the app already exists.

-- Entities
INSERT OR IGNORE INTO entities (key, kind, schema, read_action, write_action) VALUES
  ('temp_a', 'measurement', '{"type":"number","unit":"°C","format":"1dp"}', 'temp', NULL),
  ('temp_b', 'measurement', '{"type":"number","unit":"°C","format":"1dp"}', 'temp', NULL),
  ('fan',    'actuator',    '{"type":"boolean"}',                          'fan_state', 'set_fan'),
  ('note2',  'note',        '{"type":"string","max":200}',                  NULL, 'note');

-- Page
INSERT OR IGNORE INTO layouts (slug, title, hints)
VALUES ('complex', 'Device Dashboard', '{"sidebar_width":"340px","max_width":"1200px"}');

-- Widgets (regions: chrome|header|main|sidebar|footer)
WITH page AS (SELECT id FROM layouts WHERE slug='complex')
INSERT INTO widgets (layout_id, region, ord, widget_kind, entity_key, label, hints)
SELECT id, 'header', 0, 'heading', NULL, 'More Complex Device Dashboard', '{"level":1}' FROM page UNION ALL
SELECT id, 'sidebar', 0, 'value',  'temp_a', 'Temp A', '{"style":"stat"}' FROM page UNION ALL
SELECT id, 'sidebar', 1, 'value',  'temp_b', 'Temp B', '{"style":"stat"}' FROM page UNION ALL
SELECT id, 'sidebar', 2, 'divider',NULL, NULL, '{}' FROM page UNION ALL
SELECT id, 'sidebar', 3, 'form',   'note2',  'Send Note', '{"fields":[{"name":"text","placeholder":"Type a note…"}]}' FROM page UNION ALL
SELECT id, 'main',    0, 'heading',NULL, 'Controls', '{"level":2}' FROM page UNION ALL
SELECT id, 'main',    1, 'button', 'temp_a', 'Read Temp A', '{"op":"read"}' FROM page UNION ALL
SELECT id, 'main',    2, 'button', 'temp_b', 'Read Temp B', '{"op":"read"}' FROM page UNION ALL
SELECT id, 'main',    3, 'button', 'fan',    'Fan ON',      '{"op":"write","value":true}' FROM page UNION ALL
SELECT id, 'main',    4, 'button', 'fan',    'Fan OFF',     '{"op":"write","value":false}' FROM page;
