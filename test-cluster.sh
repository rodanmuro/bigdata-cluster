#!/bin/bash

echo "=================================================="
echo "  PRUEBAS DE INTEGRACION - CLUSTER BIG DATA"
echo "=================================================="

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

# ─── SERVICIOS HTTP ───────────────────────────────
echo ""
echo "[ SERVICIOS HTTP ]"

for entry in "9870:Hadoop NameNode" "9864:DataNode 1" "9865:DataNode 2" "10002:Hive Web UI" "8888:Hue" "8081:Spark Master" "8082:Spark Worker 1" "8083:Spark Worker 2" "8084:Jupyter" "8088:Superset"; do
    PORT="${entry%%:*}"
    NAME="${entry##*:}"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:$PORT)
    [[ "$CODE" =~ ^(200|302)$ ]] && check ok "$NAME (HTTP $CODE)" || check fail "$NAME (HTTP $CODE)"
done

# ─── HADOOP ───────────────────────────────────────
echo ""
echo "[ HADOOP / HDFS ]"

DN=$(curl -s "http://localhost:9870/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo" | python3 -c "import sys,json; print(len(json.loads(json.load(sys.stdin)['beans'][0]['LiveNodes'])))" 2>/dev/null)
[ "$DN" = "2" ] && check ok "DataNodes vivos: $DN" || check fail "DataNodes vivos: $DN"

docker exec hadoop-namenode hdfs dfs -mkdir -p /test-ci 2>/dev/null
docker exec hadoop-namenode bash -c "echo 'test' | hdfs dfs -put - /test-ci/test.txt" 2>/dev/null
CONTENT=$(docker exec hadoop-namenode hdfs dfs -cat /test-ci/test.txt 2>/dev/null)
[[ "$CONTENT" == "test" ]] && check ok "Escritura/Lectura HDFS" || check fail "Escritura/Lectura HDFS"
docker exec hadoop-namenode hdfs dfs -rm -r /test-ci 2>/dev/null

# ─── HIVE ─────────────────────────────────────────
echo ""
echo "[ HIVE ]"

HIVE_DBS=$(docker exec hive-server bash -c "beeline -u 'jdbc:hive2://localhost:10000' -e 'SHOW DATABASES;' 2>/dev/null" | grep -c "default")
[ "$HIVE_DBS" -ge 1 ] && check ok "Conexión HiveServer2" || check fail "Conexión HiveServer2"

docker exec hive-server bash -c "beeline -u 'jdbc:hive2://localhost:10000' -e 'CREATE DATABASE IF NOT EXISTS test_ci; USE test_ci; CREATE TABLE IF NOT EXISTS t (id INT); INSERT INTO t VALUES (1); SELECT COUNT(*) FROM t; DROP DATABASE test_ci CASCADE;' 2>/dev/null" | grep -q "1" && check ok "CRUD completo Hive" || check fail "CRUD completo Hive"

# ─── PYSPARK ──────────────────────────────────────
echo ""
echo "[ PYSPARK + SPARK CLUSTER ]"

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

# ─── HUE ──────────────────────────────────────────
echo ""
echo "[ HUE ]"

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

# ─── SUPERSET ─────────────────────────────────────
echo ""
echo "[ SUPERSET ]"

HEALTH=$(curl -s http://localhost:8088/health)
[ "$HEALTH" = "OK" ] && check ok "Health check" || check fail "Health check"

JWT=$(curl -s -X POST http://localhost:8088/api/v1/security/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin","provider":"db"}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','FALLO'))" 2>/dev/null)
[ "$JWT" != "FALLO" ] && check ok "Login + JWT token" || check fail "Login + JWT token"

PYHIVE=$(docker exec superset bash -c "/app/.venv/bin/python -c 'import pyhive; print(\"OK\")'" 2>/dev/null)
[ "$PYHIVE" = "OK" ] && check ok "pyhive en virtualenv" || check fail "pyhive en virtualenv"

# ─── RESUMEN ──────────────────────────────────────
echo ""
echo "=================================================="
TOTAL=$((PASS+FAIL))
echo "  RESULTADO: $PASS/$TOTAL tests pasaron"
[ "$FAIL" -eq 0 ] && echo "  CLUSTER OPERATIVO AL 100%" || echo "  ATENCION: $FAIL test(s) fallaron"
echo "=================================================="
