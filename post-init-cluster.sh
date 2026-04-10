#!/bin/bash

PROFILE="${1:-full}"

echo "========================================"
echo " Inicialización del Clúster - $PROFILE"
echo "========================================"

# ─── FUNCIONES ────────────────────────────────────

init_hadoop() {
    echo ""
    echo "[HADOOP] Creando directorios en HDFS..."
    docker exec hadoop-namenode hdfs dfs -mkdir -p /user/admin
    docker exec hadoop-namenode hdfs dfs -chown admin:admin /user/admin
    docker exec hadoop-namenode hdfs dfs -mkdir -p /user/hive/warehouse
    docker exec hadoop-namenode hdfs dfs -chown admin:admin /user/hive/warehouse
    echo "[HADOOP] Directorios creados."
}

init_hive() {
    echo ""
    echo "[HIVE] Inicializando esquema del metastore..."
    docker exec hive-server /opt/hive/bin/schematool -initSchema -dbType hive -metaDbType postgres -url jdbc:hive2://localhost:10000/default
    echo "[HIVE] Metastore inicializado."
}

init_hue() {
    echo ""
    echo "[HUE] Ejecutando migraciones de base de datos..."
    docker exec hue bash -c "cd /usr/share/hue && ./build/env/bin/hue migrate"
    echo "[HUE] Migraciones completadas."
}

download_flink_jars() {
    echo ""
    echo "[FLINK] Verificando JARs necesarios..."
    mkdir -p flink-jars

    MAVEN="https://repo1.maven.org/maven2"

    declare -A JARS=(
        ["flink-sql-connector-kafka-3.3.0-1.19.jar"]="$MAVEN/org/apache/flink/flink-sql-connector-kafka/3.3.0-1.19/flink-sql-connector-kafka-3.3.0-1.19.jar"
        ["flink-shaded-hadoop-2-uber-2.8.3-10.0.jar"]="$MAVEN/org/apache/flink/flink-shaded-hadoop-2-uber/2.8.3-10.0/flink-shaded-hadoop-2-uber-2.8.3-10.0.jar"
        ["flink-connector-jdbc-3.2.0-1.19.jar"]="$MAVEN/org/apache/flink/flink-connector-jdbc/3.2.0-1.19/flink-connector-jdbc-3.2.0-1.19.jar"
    )

    for JAR in "${!JARS[@]}"; do
        if [ -f "flink-jars/$JAR" ]; then
            echo "[FLINK] $JAR ya existe, omitiendo descarga."
        else
            echo "[FLINK] Descargando $JAR..."
            curl -fsSL -o "flink-jars/$JAR" "${JARS[$JAR]}"
            echo "[FLINK] $JAR descargado."
        fi
    done
    echo "[FLINK] JARs listos."
}

init_flink() {
    echo ""
    echo "[FLINK] Esperando a que el JobManager esté listo..."
    for i in $(seq 1 20); do
        curl -s http://localhost:8085/overview > /dev/null 2>&1 && break
        echo "[FLINK] Intento $i/20 - esperando 5 segundos..."
        sleep 5
    done

    echo "[FLINK] Creando directorio de checkpoints en HDFS..."
    docker exec hadoop-namenode hdfs dfs -mkdir -p /flink/checkpoints
    docker exec hadoop-namenode hdfs dfs -mkdir -p /flink/savepoints

    echo "[FLINK] Enviando jobs SQL..."
    docker exec flink-jobmanager ./bin/sql-client.sh -f /opt/flink/jobs/ventas_por_minuto.sql 2>&1 | grep -E "Job ID|ERROR"
    docker exec flink-jobmanager ./bin/sql-client.sh -f /opt/flink/jobs/eventos_por_tipo.sql 2>&1 | grep -E "Job ID|ERROR"
    docker exec flink-jobmanager ./bin/sql-client.sh -f /opt/flink/jobs/actividad_productos.sql 2>&1 | grep -E "Job ID|ERROR"
    docker exec flink-jobmanager ./bin/sql-client.sh -f /opt/flink/jobs/sesiones_navegadores.sql 2>&1 | grep -E "Job ID|ERROR"

    echo "[FLINK] Jobs enviados."
}

init_grafana() {
    echo ""
    echo "[GRAFANA] Esperando a que Grafana esté listo..."
    for i in $(seq 1 20); do
        curl -s http://localhost:3000/api/health | grep -q "ok" && break
        echo "[GRAFANA] Intento $i/20 - esperando 5 segundos..."
        sleep 5
    done
    echo "[GRAFANA] Grafana listo — dashboard disponible en http://localhost:3000"
    echo "[GRAFANA] Credenciales: admin / admin"
}

init_postgres_streaming() {
    echo ""
    echo "[POSTGRES-STREAMING] Esperando a que PostgreSQL esté listo..."
    for i in $(seq 1 20); do
        docker exec postgres-streaming pg_isready -U flink > /dev/null 2>&1 && break
        echo "[POSTGRES-STREAMING] Intento $i/20 - esperando 3 segundos..."
        sleep 3
    done

    echo "[POSTGRES-STREAMING] Creando tablas..."
    docker exec postgres-streaming psql -U flink -d streaming -c "
        CREATE TABLE IF NOT EXISTS ventas_por_minuto (
            product_id      VARCHAR(50),
            product         VARCHAR(100),
            total_compras   BIGINT,
            revenue         DOUBLE PRECISION,
            ventana_inicio  TIMESTAMP,
            ventana_fin     TIMESTAMP,
            PRIMARY KEY (product_id, ventana_inicio)
        );

        CREATE TABLE IF NOT EXISTS eventos_por_tipo (
            tipo            VARCHAR(50),
            total_eventos   BIGINT,
            ventana_inicio  TIMESTAMP,
            ventana_fin     TIMESTAMP,
            PRIMARY KEY (tipo, ventana_inicio)
        );

        CREATE TABLE IF NOT EXISTS actividad_productos (
            product_id      VARCHAR(50),
            product         VARCHAR(100),
            tipo            VARCHAR(50),
            total           BIGINT,
            ventana_inicio  TIMESTAMP,
            ventana_fin     TIMESTAMP,
            PRIMARY KEY (product_id, tipo, ventana_inicio)
        );

        CREATE TABLE IF NOT EXISTS sesiones_navegadores (
            ip              VARCHAR(50),
            browser         VARCHAR(50),
            os              VARCHAR(50),
            total_eventos   BIGINT,
            ventana_inicio  TIMESTAMP,
            ventana_fin     TIMESTAMP,
            PRIMARY KEY (ip, browser, os, ventana_inicio)
        );
    "
    echo "[POSTGRES-STREAMING] Tablas creadas."
}

init_streaming() {
    echo ""
    echo "[KAFKA] Esperando a que el broker esté listo..."
    for i in $(seq 1 20); do
        docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list > /dev/null 2>&1 && break
        echo "[KAFKA] Intento $i/20 - esperando 5 segundos..."
        sleep 5
    done

    echo "[KAFKA] Creando topics..."
    docker exec kafka /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server kafka:9092 \
        --create --if-not-exists \
        --topic eventos-tienda \
        --partitions 6 \
        --replication-factor 1

    docker exec kafka /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server kafka:9092 \
        --create --if-not-exists \
        --topic metricas-procesadas \
        --partitions 3 \
        --replication-factor 1

    echo "[KAFKA] Topics creados:"
    docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list

    download_flink_jars
    init_postgres_streaming
    echo ""
    echo "[FLINK] Reiniciando Flink para cargar los JARs descargados..."
    docker restart flink-jobmanager flink-taskmanager
    init_flink
    init_grafana
}

# ─── EJECUCIÓN POR PROFILE ────────────────────────

case "$PROFILE" in
    hadoop)
        init_hadoop
        ;;
    hive)
        init_hadoop
        init_hive
        init_hue
        ;;
    spark)
        init_hadoop
        ;;
    streaming)
        init_hadoop
        init_streaming
        ;;
    full)
        init_hadoop
        init_hive
        init_hue
        init_streaming
        ;;
    *)
        echo ""
        echo "Profile no reconocido: '$PROFILE'"
        echo ""
        echo "Uso: ./post-init-cluster.sh [profile]"
        echo ""
        echo "Profiles disponibles:"
        echo "  hadoop    - Solo inicializa directorios HDFS"
        echo "  hive      - HDFS + metastore Hive + migraciones Hue"
        echo "  spark     - Solo inicializa directorios HDFS"
        echo "  streaming - HDFS + topics Kafka + JARs Flink + tablas PostgreSQL"
        echo "  full      - Inicialización completa (por defecto)"
        exit 1
        ;;
esac

echo ""
echo "========================================"
echo " Inicialización completada: $PROFILE"
echo "========================================"
echo ""
echo "Nota: si algún paso falló por conexión, espera"
echo "unos segundos y vuelve a ejecutar el script."
