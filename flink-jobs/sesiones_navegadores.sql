-- ─────────────────────────────────────────────────────────────────
-- Job: sesiones_navegadores
-- Cuenta eventos por browser y sistema operativo.
-- Solo procesa eventos de la tienda web (browser IS NOT NULL).
-- Cuando corre el simulador estos eventos se descartan silenciosamente.
-- ─────────────────────────────────────────────────────────────────

-- 1. Tabla fuente: topic Kafka con campos extendidos de la tienda web
CREATE TABLE IF NOT EXISTS eventos_tienda (
    type        STRING,
    product_id  STRING,
    product     STRING,
    category    STRING,
    price       DOUBLE,
    quantity    INT,
    total       DOUBLE,
    user_id     STRING,
    browser     STRING,
    os          STRING,
    ip          STRING,
    event_time  AS TO_TIMESTAMP(`timestamp`, 'yyyy-MM-dd''T''HH:mm:ss''Z'''),
    `timestamp` STRING,
    WATERMARK FOR event_time AS event_time - INTERVAL '2' SECOND
) WITH (
    'connector'                     = 'kafka',
    'topic'                         = 'eventos-tienda',
    'properties.bootstrap.servers'  = 'kafka:9092',
    'properties.group.id'           = 'flink-sesiones',
    'scan.startup.mode'             = 'earliest-offset',
    'format'                        = 'json',
    'json.ignore-parse-errors'      = 'true',
    'scan.watermark.idle-timeout'   = '5 s'
);

-- 2. Tabla destino: PostgreSQL
CREATE TABLE IF NOT EXISTS sesiones_navegadores (
    ip             STRING,
    browser        STRING,
    os             STRING,
    total_eventos  BIGINT,
    ventana_inicio TIMESTAMP(3),
    ventana_fin    TIMESTAMP(3),
    PRIMARY KEY (ip, browser, os, ventana_inicio) NOT ENFORCED
) WITH (
    'connector'  = 'jdbc',
    'url'        = 'jdbc:postgresql://postgres-streaming:5432/streaming',
    'table-name' = 'sesiones_navegadores',
    'username'   = 'flink',
    'password'   = 'flink'
);

-- 3. Job: cuenta eventos por IP, browser y OS cada segundo
--    WHERE browser IS NOT NULL  →  descarta eventos del simulador
INSERT INTO sesiones_navegadores
SELECT
    ip,
    browser,
    os,
    COUNT(*)                                                AS total_eventos,
    TUMBLE_START(event_time, INTERVAL '1' SECOND)           AS ventana_inicio,
    TUMBLE_END(event_time, INTERVAL '1' SECOND)             AS ventana_fin
FROM eventos_tienda
WHERE browser IS NOT NULL
GROUP BY
    ip,
    browser,
    os,
    TUMBLE(event_time, INTERVAL '1' SECOND);
