-- ─────────────────────────────────────────────────────────────────
-- Job: actividad_productos
-- Cuenta product_hover, add_to_cart y purchase por producto.
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
    'properties.group.id'           = 'flink-actividad',
    'scan.startup.mode'             = 'earliest-offset',
    'format'                        = 'json',
    'json.ignore-parse-errors'      = 'true',
    'scan.watermark.idle-timeout'   = '5 s'
);

-- 2. Tabla destino: PostgreSQL
CREATE TABLE IF NOT EXISTS actividad_productos (
    product_id     STRING,
    product        STRING,
    tipo           STRING,
    total          BIGINT,
    ventana_inicio TIMESTAMP(3),
    ventana_fin    TIMESTAMP(3),
    PRIMARY KEY (product_id, tipo, ventana_inicio) NOT ENFORCED
) WITH (
    'connector'  = 'jdbc',
    'url'        = 'jdbc:postgresql://postgres-streaming:5432/streaming',
    'table-name' = 'actividad_productos',
    'username'   = 'flink',
    'password'   = 'flink'
);

-- 3. Job: cuenta interacciones por producto cada segundo
--    WHERE browser IS NOT NULL  →  descarta eventos del simulador
INSERT INTO actividad_productos
SELECT
    product_id,
    MAX(product)                                            AS product,
    type                                                    AS tipo,
    COUNT(*)                                                AS total,
    TUMBLE_START(event_time, INTERVAL '1' SECOND)           AS ventana_inicio,
    TUMBLE_END(event_time, INTERVAL '1' SECOND)             AS ventana_fin
FROM eventos_tienda
WHERE browser IS NOT NULL
  AND product_id <> ''
  AND type IN ('product_hover', 'add_to_cart', 'purchase')
GROUP BY
    product_id,
    type,
    TUMBLE(event_time, INTERVAL '1' SECOND);
