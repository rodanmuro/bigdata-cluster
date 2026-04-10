-- ─────────────────────────────────────────────────────────────────
-- Job: ventas_por_minuto
-- Lee eventos de compra desde Kafka y calcula revenue por producto
-- cada minuto usando ventanas tumbling. Escribe en PostgreSQL.
-- ─────────────────────────────────────────────────────────────────

-- 1. Tabla fuente: topic Kafka eventos-tienda
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
    'properties.group.id'           = 'flink-ventas',
    'scan.startup.mode'             = 'earliest-offset',
    'format'                        = 'json',
    'json.ignore-parse-errors'      = 'true',
    'scan.watermark.idle-timeout'   = '5 s'
);

-- 2. Tabla destino: PostgreSQL
CREATE TABLE IF NOT EXISTS ventas_por_minuto (
    product_id      STRING,
    product         STRING,
    total_compras   BIGINT,
    revenue         DOUBLE,
    ventana_inicio  TIMESTAMP(3),
    ventana_fin     TIMESTAMP(3),
    PRIMARY KEY (product_id, ventana_inicio) NOT ENFORCED
) WITH (
    'connector'  = 'jdbc',
    'url'        = 'jdbc:postgresql://postgres-streaming:5432/streaming',
    'table-name' = 'ventas_por_minuto',
    'username'   = 'flink',
    'password'   = 'flink'
);

-- 3. Job: agrega compras por producto cada minuto
INSERT INTO ventas_por_minuto
SELECT
    product_id,
    MAX(product)                                        AS product,
    COUNT(*)                                            AS total_compras,
    SUM(total)                                          AS revenue,
    TUMBLE_START(event_time, INTERVAL '1' SECOND)       AS ventana_inicio,
    TUMBLE_END(event_time, INTERVAL '1' SECOND)         AS ventana_fin
FROM eventos_tienda
WHERE type = 'purchase'
GROUP BY
    product_id,
    TUMBLE(event_time, INTERVAL '1' SECOND);
