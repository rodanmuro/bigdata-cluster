-- ─────────────────────────────────────────────────────────────────
-- Job: eventos_por_tipo
-- Cuenta todos los eventos por tipo cada 30 segundos.
-- Útil para ver en tiempo real cuántos page_views, purchases,
-- cart_abandons, etc. están ocurriendo.
-- ─────────────────────────────────────────────────────────────────

-- 1. Tabla fuente: reutiliza el mismo topic Kafka
CREATE TABLE IF NOT EXISTS eventos_tienda (
    type        STRING,
    product_id  STRING,
    product     STRING,
    category    STRING,
    price       DOUBLE,
    quantity    INT,
    total       DOUBLE,
    user_id     STRING,
    event_time  AS TO_TIMESTAMP(`timestamp`, 'yyyy-MM-dd''T''HH:mm:ss''Z'''),
    `timestamp` STRING,
    WATERMARK FOR event_time AS event_time - INTERVAL '2' SECOND
) WITH (
    'connector'                     = 'kafka',
    'topic'                         = 'eventos-tienda',
    'properties.bootstrap.servers'  = 'kafka:9092',
    'properties.group.id'           = 'flink-eventos',
    'scan.startup.mode'             = 'earliest-offset',
    'format'                        = 'json',
    'json.ignore-parse-errors'      = 'true'
);

-- 2. Tabla destino: PostgreSQL
CREATE TABLE IF NOT EXISTS eventos_por_tipo (
    tipo            STRING,
    total_eventos   BIGINT,
    ventana_inicio  TIMESTAMP(3),
    ventana_fin     TIMESTAMP(3),
    PRIMARY KEY (tipo, ventana_inicio) NOT ENFORCED
) WITH (
    'connector'  = 'jdbc',
    'url'        = 'jdbc:postgresql://postgres-streaming:5432/streaming',
    'table-name' = 'eventos_por_tipo',
    'username'   = 'flink',
    'password'   = 'flink'
);

-- 3. Job: cuenta eventos por tipo cada 30 segundos
INSERT INTO eventos_por_tipo
SELECT
    type                                                    AS tipo,
    COUNT(*)                                                AS total_eventos,
    TUMBLE_START(event_time, INTERVAL '1' SECOND)           AS ventana_inicio,
    TUMBLE_END(event_time, INTERVAL '1' SECOND)             AS ventana_fin
FROM eventos_tienda
GROUP BY
    type,
    TUMBLE(event_time, INTERVAL '1' SECOND);
