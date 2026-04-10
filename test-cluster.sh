#!/bin/bash

PROFILE="${1:-full}"

PASS=0
FAIL=0

check() {
    if [ "$1" = "ok" ]; then
        echo "    OK - $2"
        PASS=$((PASS+1))
    else
        echo "    FALLO - $2"
        FAIL=$((FAIL+1))
    fi
}

check_http() {
    local PORT=$1
    local NAME=$2
    local CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:$PORT)
    [[ "$CODE" =~ ^(200|302)$ ]] && check ok "$NAME (HTTP $CODE)" || check fail "$NAME (HTTP $CODE)"
}

echo "=================================================="
echo "  PRUEBAS DE INTEGRACION - PROFILE: $PROFILE"
echo "=================================================="

# ─── HADOOP ───────────────────────────────────────
test_hadoop() {
    echo ""
    echo "[ HADOOP / HDFS ]"

    check_http 9870 "Hadoop NameNode"
    check_http 9864 "DataNode 1"
    check_http 9865 "DataNode 2"

    DN=$(curl -s "http://localhost:9870/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo" | python3 -c "import sys,json; print(len(json.loads(json.load(sys.stdin)['beans'][0]['LiveNodes'])))" 2>/dev/null)
    [ "$DN" = "2" ] && check ok "DataNodes vivos: $DN" || check fail "DataNodes vivos: $DN"

    docker exec hadoop-namenode hdfs dfs -mkdir -p /test-ci 2>/dev/null
    docker exec hadoop-namenode bash -c "echo 'test' | hdfs dfs -put - /test-ci/test.txt" 2>/dev/null
    CONTENT=$(docker exec hadoop-namenode hdfs dfs -cat /test-ci/test.txt 2>/dev/null)
    [[ "$CONTENT" == "test" ]] && check ok "Escritura/Lectura HDFS" || check fail "Escritura/Lectura HDFS"
    docker exec hadoop-namenode hdfs dfs -rm -r /test-ci 2>/dev/null
}

# ─── HIVE ─────────────────────────────────────────
test_hive() {
    echo ""
    echo "[ HIVE ]"

    check_http 10002 "Hive Web UI"

    HIVE_DBS=$(docker exec hive-server bash -c "beeline -u 'jdbc:hive2://localhost:10000' -e 'SHOW DATABASES;' 2>/dev/null" | grep -c "default")
    [ "$HIVE_DBS" -ge 1 ] && check ok "Conexión HiveServer2" || check fail "Conexión HiveServer2"

    docker exec hive-server bash -c "beeline -u 'jdbc:hive2://localhost:10000' -e 'CREATE DATABASE IF NOT EXISTS test_ci; USE test_ci; CREATE TABLE IF NOT EXISTS t (id INT); INSERT INTO t VALUES (1); SELECT COUNT(*) FROM t; DROP DATABASE test_ci CASCADE;' 2>/dev/null" | grep -q "1" && check ok "CRUD completo Hive" || check fail "CRUD completo Hive"
}

# ─── HUE ──────────────────────────────────────────
test_hue() {
    echo ""
    echo "[ HUE ]"

    check_http 8888 "Hue"

    COOKIE_JAR=$(mktemp)
    CSRF=$(curl -s -c "$COOKIE_JAR" http://localhost:8888/hue/accounts/login/ | grep -o 'csrftoken=[^;]*' | head -1 | cut -d= -f2)
    [ -z "$CSRF" ] && CSRF=$(cat "$COOKIE_JAR" | grep csrftoken | awk '{print $7}')
    LOGIN=$(curl -s -o /dev/null -w "%{http_code}" -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
      -X POST http://localhost:8888/hue/accounts/login/ \
      -H "Referer: http://localhost:8888/hue/accounts/login/" \
      -d "username=admin&password=admin&csrfmiddlewaretoken=$CSRF")
    [ "$LOGIN" = "302" ] && check ok "Login Hue" || check fail "Login Hue (HTTP $LOGIN)"

    HDFS_HUE=$(curl -s -b "$COOKIE_JAR" "http://localhost:8888/filebrowser/view=/?format=json" | python3 -c "import sys,json; files=[f['name'] for f in json.load(sys.stdin).get('files',[]) if f['name'] not in ['.','..']]; print(files)" 2>/dev/null)
    [ -n "$HDFS_HUE" ] && check ok "HDFS desde Hue: $HDFS_HUE" || check fail "HDFS desde Hue"

    HIVE_HUE=$(docker exec hue bash -c "curl -s -o /dev/null -w '%{http_code}' http://hive-server:10002" 2>/dev/null)
    [ "$HIVE_HUE" = "200" ] && check ok "Hue alcanza HiveServer2" || check fail "Hue alcanza HiveServer2"
    rm -f "$COOKIE_JAR"
}

# ─── SPARK ────────────────────────────────────────
test_spark() {
    echo ""
    echo "[ SPARK ]"

    check_http 8081 "Spark Master"
    check_http 8082 "Spark Worker 1"
    check_http 8083 "Spark Worker 2"
    check_http 8084 "Jupyter Notebook"

    SPARK_RESULT=$(docker exec python-pyspark4-jupyter python -c "
from pyspark.sql import SparkSession
spark = SparkSession.builder \
    .appName('test-ci') \
    .master('spark://spark-master:7077') \
    .config('spark.driver.host', 'python-pyspark4-jupyter') \
    .config('spark.driver.bindAddress', '0.0.0.0') \
    .config('spark.driver.port', '7078') \
    .config('spark.blockManager.port', '7079') \
    .getOrCreate()
rdd = spark.sparkContext.parallelize(range(1, 101))
print(rdd.reduce(lambda a,b: a+b))
spark.stop()
" 2>/dev/null)
    [ "$SPARK_RESULT" = "5050" ] && check ok "Operación distribuida Spark (suma 1-100 = $SPARK_RESULT)" || check fail "Operación distribuida Spark (resultado: $SPARK_RESULT)"

    HDFS_SPARK=$(docker exec python-pyspark4-jupyter python -c "
from pyspark.sql import SparkSession
spark = SparkSession.builder.appName('test-hdfs').master('local').getOrCreate()
sc = spark.sparkContext
sc._jvm.org.apache.hadoop.fs.FileSystem.get(sc._jvm.java.net.URI('hdfs://hadoop-namenode:9000'),sc._jsc.hadoopConfiguration()).getStatus(sc._jvm.org.apache.hadoop.fs.Path('/'))
print('OK')
spark.stop()
" 2>/dev/null)
    [ "$HDFS_SPARK" = "OK" ] && check ok "PySpark → HDFS" || check fail "PySpark → HDFS"
}

# ─── SUPERSET ─────────────────────────────────────
test_superset() {
    echo ""
    echo "[ SUPERSET ]"

    check_http 8088 "Superset"

    HEALTH=$(curl -s http://localhost:8088/health)
    [ "$HEALTH" = "OK" ] && check ok "Health check" || check fail "Health check"

    JWT=$(curl -s -X POST http://localhost:8088/api/v1/security/login \
      -H "Content-Type: application/json" \
      -d '{"username":"admin","password":"admin","provider":"db"}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','FALLO'))" 2>/dev/null)
    [ "$JWT" != "FALLO" ] && check ok "Login + JWT token" || check fail "Login + JWT token"

    PYHIVE=$(docker exec superset bash -c "/app/.venv/bin/python -c 'import pyhive; print(\"OK\")'" 2>/dev/null)
    [ "$PYHIVE" = "OK" ] && check ok "pyhive en virtualenv" || check fail "pyhive en virtualenv"
}

# ─── STREAMING ────────────────────────────────────
test_streaming() {
    echo ""
    echo "[ KAFKA ]"

    check_http 8090 "Kafka UI"

    TOPICS=$(docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list 2>/dev/null)
    echo "$TOPICS" | grep -q "eventos-tienda"     && check ok "Topic eventos-tienda existe"     || check fail "Topic eventos-tienda no encontrado"
    echo "$TOPICS" | grep -q "metricas-procesadas" && check ok "Topic metricas-procesadas existe" || check fail "Topic metricas-procesadas no encontrado"

    echo "test-ci" | docker exec -i kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:9092 --topic eventos-tienda > /dev/null 2>&1
    MSG=$(docker exec kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic eventos-tienda --from-beginning --max-messages 1 --timeout-ms 5000 2>/dev/null)
    [ "$MSG" = "test-ci" ] && check ok "Produce/Consume Kafka" || check fail "Produce/Consume Kafka"

    echo ""
    echo "[ FLINK ]"

    check_http 8085 "Flink JobManager"

    TM=$(curl -s http://localhost:8085/taskmanagers 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('taskmanagers', [])))" 2>/dev/null)
    [ "$TM" -ge 1 ] 2>/dev/null && check ok "TaskManager registrado ($TM)" || check fail "TaskManager no disponible"

    SLOTS=$(curl -s http://localhost:8085/overview 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('slots-available',0))" 2>/dev/null)
    [ "$SLOTS" -ge 1 ] 2>/dev/null && check ok "Slots disponibles: $SLOTS" || check fail "Sin slots disponibles"

    echo ""
    echo "[ POSTGRES STREAMING ]"

    TABLES=$(docker exec postgres-streaming psql -U flink -d streaming -c "\dt" 2>/dev/null)
    echo "$TABLES" | grep -q "ventas_por_minuto"     && check ok "Tabla ventas_por_minuto existe"     || check fail "Tabla ventas_por_minuto no encontrada"
    echo "$TABLES" | grep -q "eventos_por_tipo"      && check ok "Tabla eventos_por_tipo existe"      || check fail "Tabla eventos_por_tipo no encontrada"
    echo "$TABLES" | grep -q "actividad_productos"   && check ok "Tabla actividad_productos existe"   || check fail "Tabla actividad_productos no encontrada"
    echo "$TABLES" | grep -q "sesiones_navegadores"  && check ok "Tabla sesiones_navegadores existe"  || check fail "Tabla sesiones_navegadores no encontrada"

    echo ""
    echo "[ TIENDA WEB ]"

    check_http 8091 "Tienda Web"

    TIENDA=$(curl -s http://localhost:8091/ 2>/dev/null | grep -c "TiendaStream")
    [ "$TIENDA" -ge 1 ] 2>/dev/null && check ok "Página principal cargada" || check fail "Página principal no disponible"

    API=$(curl -s -X POST http://localhost:8091/api/evento \
        -H "Content-Type: application/json" \
        -d '{"type":"page_view","product_id":"","product":"","category":"","price":0,"quantity":0,"total":0,"user_id":"test-ci","browser":"test","os":"test"}' \
        2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('ok','false'))" 2>/dev/null)
    [ "$API" = "True" ] && check ok "API /api/evento responde" || check fail "API /api/evento no responde"

    echo ""
    echo "[ GRAFANA ]"

    check_http 3000 "Grafana"

    HEALTH=$(curl -s http://localhost:3000/api/health | python3 -c "import sys,json; print(json.load(sys.stdin).get('database','error'))" 2>/dev/null)
    [ "$HEALTH" = "ok" ] && check ok "Grafana database: ok" || check fail "Grafana database: $HEALTH"

    DS=$(curl -s -u admin:admin http://localhost:3000/api/datasources | python3 -c "import sys,json; ds=[d['name'] for d in json.load(sys.stdin)]; print('ok' if 'PostgreSQL-Streaming' in ds else 'fail')" 2>/dev/null)
    [ "$DS" = "ok" ] && check ok "Datasource PostgreSQL-Streaming configurado" || check fail "Datasource PostgreSQL-Streaming no encontrado"

    DASH=$(curl -s -u admin:admin "http://localhost:3000/api/search?query=Streaming" | python3 -c "import sys,json; results=json.load(sys.stdin); print('ok' if len(results)>0 else 'fail')" 2>/dev/null)
    [ "$DASH" = "ok" ] && check ok "Dashboard Streaming cargado" || check fail "Dashboard Streaming no encontrado"
}

# ─── EJECUCIÓN POR PROFILE ────────────────────────

case "$PROFILE" in
    hadoop)
        test_hadoop
        ;;
    hive)
        test_hadoop
        test_hive
        test_hue
        ;;
    spark)
        test_hadoop
        test_spark
        ;;
    streaming)
        test_hadoop
        test_streaming
        ;;
    full)
        test_hadoop
        test_hive
        test_hue
        test_spark
        test_superset
        test_streaming
        ;;
    *)
        echo ""
        echo "Profile no reconocido: '$PROFILE'"
        echo ""
        echo "Uso: ./test-cluster.sh [profile]"
        echo ""
        echo "Profiles disponibles:"
        echo "  hadoop    - Prueba Hadoop/HDFS"
        echo "  hive      - Prueba Hadoop + Hive + Hue"
        echo "  spark     - Prueba Hadoop + Spark + Jupyter"
        echo "  streaming - Prueba Hadoop + Kafka + Flink + PostgreSQL streaming"
        echo "  full      - Prueba todo el clúster (por defecto)"
        exit 1
        ;;
esac

# ─── RESUMEN ──────────────────────────────────────
echo ""
echo "=================================================="
TOTAL=$((PASS+FAIL))
echo "  RESULTADO: $PASS/$TOTAL tests pasaron"
[ "$FAIL" -eq 0 ] && echo "  CLUSTER OPERATIVO AL 100% [$PROFILE]" || echo "  ATENCION: $FAIL test(s) fallaron"
echo "=================================================="
