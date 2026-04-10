@echo off
setlocal enabledelayedexpansion

set PROFILE=%1
if "%PROFILE%"=="" set PROFILE=full

set PASS=0
set FAIL=0

echo ==================================================
echo   PRUEBAS DE INTEGRACION - PROFILE: %PROFILE%
echo ==================================================

if "%PROFILE%"=="hadoop"    goto do_hadoop
if "%PROFILE%"=="hive"      goto do_hive
if "%PROFILE%"=="spark"     goto do_spark
if "%PROFILE%"=="streaming" goto do_streaming
if "%PROFILE%"=="full"      goto do_full

echo.
echo Profile no reconocido: '%PROFILE%'
echo.
echo Uso: test-cluster.bat [profile]
echo.
echo Profiles disponibles:
echo   hadoop    - Prueba Hadoop/HDFS
echo   hive      - Prueba Hadoop + Hive + Hue
echo   spark     - Prueba Hadoop + Spark + Jupyter
echo   streaming - Prueba Hadoop + Kafka + Flink + PostgreSQL streaming
echo   full      - Prueba todo el cluster (por defecto)
goto end

:do_hadoop
call :test_hadoop
goto summary

:do_hive
call :test_hadoop
call :test_hive
call :test_hue
goto summary

:do_spark
call :test_hadoop
call :test_spark
goto summary

:do_streaming
call :test_hadoop
call :test_streaming
goto summary

:do_full
call :test_hadoop
call :test_hive
call :test_hue
call :test_spark
call :test_superset
call :test_streaming
goto summary

:: ─── FUNCIONES DE PRUEBA ──────────────────────────

:test_hadoop
echo.
echo [ HADOOP / HDFS ]
call :check_http 9870 "Hadoop NameNode"
call :check_http 9864 "DataNode 1"
call :check_http 9865 "DataNode 2"

docker exec hadoop-namenode hdfs dfs -mkdir -p /test-ci >nul 2>&1
docker exec hadoop-namenode bash -c "echo test | hdfs dfs -put - /test-ci/test.txt" >nul 2>&1
for /f %%i in ('docker exec hadoop-namenode hdfs dfs -cat /test-ci/test.txt 2^>nul') do set CONTENT=%%i
if "!CONTENT!"=="test" ( call :ok "Escritura/Lectura HDFS" ) else ( call :fail "Escritura/Lectura HDFS" )
docker exec hadoop-namenode hdfs dfs -rm -r /test-ci >nul 2>&1
goto :eof

:test_hive
echo.
echo [ HIVE ]
call :check_http 10002 "Hive Web UI"

for /f %%i in ('docker exec hive-server bash -c "beeline -u jdbc:hive2://localhost:10000 -e \"SHOW DATABASES;\" 2>/dev/null" 2^>nul ^| find /c "default"') do set HIVE_OK=%%i
if !HIVE_OK! GEQ 1 ( call :ok "Conexion HiveServer2" ) else ( call :fail "Conexion HiveServer2" )

docker exec hive-server bash -c "beeline -u jdbc:hive2://localhost:10000 -e \"CREATE DATABASE IF NOT EXISTS test_ci; USE test_ci; CREATE TABLE IF NOT EXISTS t (id INT); INSERT INTO t VALUES (1); SELECT COUNT(*) FROM t; DROP DATABASE test_ci CASCADE;\" 2>/dev/null" >nul 2>&1
call :ok "CRUD completo Hive"
goto :eof

:test_hue
echo.
echo [ HUE ]
call :check_http 8888 "Hue"

for /f %%i in ('docker exec hue bash -c "curl -s -o /dev/null -w %%{http_code} http://hive-server:10002" 2^>nul') do set HIVE_HUE=%%i
if "!HIVE_HUE!"=="200" ( call :ok "Hue alcanza HiveServer2" ) else ( call :fail "Hue alcanza HiveServer2" )
goto :eof

:test_spark
echo.
echo [ SPARK ]
call :check_http 8081 "Spark Master"
call :check_http 8082 "Spark Worker 1"
call :check_http 8083 "Spark Worker 2"
call :check_http 8084 "Jupyter Notebook"

for /f %%i in ('docker exec python-pyspark4-jupyter python -c "from pyspark.sql import SparkSession; spark=SparkSession.builder.appName(\"test-ci\").master(\"spark://spark-master:7077\").config(\"spark.driver.host\",\"python-pyspark4-jupyter\").config(\"spark.driver.bindAddress\",\"0.0.0.0\").config(\"spark.driver.port\",\"7078\").config(\"spark.blockManager.port\",\"7079\").getOrCreate(); print(spark.sparkContext.parallelize(range(1,101)).reduce(lambda a,b:a+b)); spark.stop()" 2^>nul') do set SPARK_RESULT=%%i
if "!SPARK_RESULT!"=="5050" ( call :ok "Operacion distribuida Spark (suma 1-100 = !SPARK_RESULT!)" ) else ( call :fail "Operacion distribuida Spark (resultado: !SPARK_RESULT!)" )

for /f %%i in ('docker exec python-pyspark4-jupyter python -c "from pyspark.sql import SparkSession; spark=SparkSession.builder.appName(\"test-hdfs\").master(\"local\").getOrCreate(); sc=spark.sparkContext; sc._jvm.org.apache.hadoop.fs.FileSystem.get(sc._jvm.java.net.URI(\"hdfs://hadoop-namenode:9000\"),sc._jsc.hadoopConfiguration()).getStatus(sc._jvm.org.apache.hadoop.fs.Path(\"/\")); print(\"OK\"); spark.stop()" 2^>nul') do set HDFS_SPARK=%%i
if "!HDFS_SPARK!"=="OK" ( call :ok "PySpark - HDFS" ) else ( call :fail "PySpark - HDFS" )
goto :eof

:test_superset
echo.
echo [ SUPERSET ]
call :check_http 8088 "Superset"

for /f %%i in ('curl -s http://localhost:8088/health') do set HEALTH=%%i
if "!HEALTH!"=="OK" ( call :ok "Health check" ) else ( call :fail "Health check" )

for /f %%i in ('docker exec superset bash -c "/app/.venv/bin/python -c \"import pyhive; print('OK')\"" 2^>nul') do set PYHIVE=%%i
if "!PYHIVE!"=="OK" ( call :ok "pyhive en virtualenv" ) else ( call :fail "pyhive en virtualenv" )
goto :eof

:test_streaming
echo.
echo [ KAFKA ]
call :check_http 8090 "Kafka UI"

docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list 2>nul | find "eventos-tienda" >nul
if !errorlevel!==0 ( call :ok "Topic eventos-tienda existe" ) else ( call :fail "Topic eventos-tienda no encontrado" )

docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list 2>nul | find "metricas-procesadas" >nul
if !errorlevel!==0 ( call :ok "Topic metricas-procesadas existe" ) else ( call :fail "Topic metricas-procesadas no encontrado" )

echo test-ci | docker exec -i kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:9092 --topic eventos-tienda >nul 2>&1
for /f "delims=" %%i in ('docker exec kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic eventos-tienda --from-beginning --max-messages 1 --timeout-ms 5000 2^>nul') do set KAFKA_MSG=%%i
if "!KAFKA_MSG!"=="test-ci" ( call :ok "Produce/Consume Kafka" ) else ( call :fail "Produce/Consume Kafka" )

echo.
echo [ FLINK ]
call :check_http 8085 "Flink JobManager"

for /f %%i in ('curl -s http://localhost:8085/taskmanagers 2^>nul ^| python -c "import sys,json; print(len(json.load(sys.stdin).get(\"taskmanagers\",[])))" 2^>nul') do set TM=%%i
if defined TM (
    if !TM! GEQ 1 ( call :ok "TaskManager registrado (!TM!)" ) else ( call :fail "TaskManager no disponible" )
) else (
    call :fail "TaskManager no disponible"
)

for /f %%i in ('curl -s http://localhost:8085/overview 2^>nul ^| python -c "import sys,json; d=json.load(sys.stdin); print(d.get(\"slots-available\",0))" 2^>nul') do set SLOTS=%%i
if defined SLOTS (
    if !SLOTS! GEQ 1 ( call :ok "Slots disponibles: !SLOTS!" ) else ( call :fail "Sin slots disponibles" )
) else (
    call :fail "Sin slots disponibles"
)

echo.
echo [ POSTGRES STREAMING ]
docker exec postgres-streaming psql -U flink -d streaming -c "\dt" 2>nul | find "ventas_por_minuto" >nul
if !errorlevel!==0 ( call :ok "Tabla ventas_por_minuto existe" ) else ( call :fail "Tabla ventas_por_minuto no encontrada" )

docker exec postgres-streaming psql -U flink -d streaming -c "\dt" 2>nul | find "eventos_por_tipo" >nul
if !errorlevel!==0 ( call :ok "Tabla eventos_por_tipo existe" ) else ( call :fail "Tabla eventos_por_tipo no encontrada" )

echo.
echo [ GRAFANA ]
call :check_http 3000 "Grafana"

for /f %%i in ('curl -s http://localhost:3000/api/health 2^>nul ^| python -c "import sys,json; print(json.load(sys.stdin).get(\"database\",\"error\"))" 2^>nul') do set GF_HEALTH=%%i
if "!GF_HEALTH!"=="ok" ( call :ok "Grafana database: ok" ) else ( call :fail "Grafana database: !GF_HEALTH!" )

for /f %%i in ('curl -s -u admin:admin http://localhost:3000/api/datasources 2^>nul ^| python -c "import sys,json; ds=[d[\"name\"] for d in json.load(sys.stdin)]; print(\"ok\" if \"PostgreSQL-Streaming\" in ds else \"fail\")" 2^>nul') do set GF_DS=%%i
if "!GF_DS!"=="ok" ( call :ok "Datasource PostgreSQL-Streaming configurado" ) else ( call :fail "Datasource PostgreSQL-Streaming no encontrado" )

for /f %%i in ('curl -s -u admin:admin "http://localhost:3000/api/search?query=Streaming" 2^>nul ^| python -c "import sys,json; results=json.load(sys.stdin); print(\"ok\" if len(results)^>0 else \"fail\")" 2^>nul') do set GF_DASH=%%i
if "!GF_DASH!"=="ok" ( call :ok "Dashboard Streaming cargado" ) else ( call :fail "Dashboard Streaming no encontrado" )
goto :eof

:: ─── HELPERS ──────────────────────────────────────

:check_http
for /f %%i in ('curl -s -o nul -w "%%{http_code}" --max-time 5 http://localhost:%1') do set CODE=%%i
if "!CODE!"=="200" ( call :ok "%~2 (HTTP !CODE!)" ) else if "!CODE!"=="302" ( call :ok "%~2 (HTTP !CODE!)" ) else ( call :fail "%~2 (HTTP !CODE!)" )
goto :eof

:ok
echo     OK - %~1
set /a PASS+=1
goto :eof

:fail
echo     FALLO - %~1
set /a FAIL+=1
goto :eof

:: ─── RESUMEN ──────────────────────────────────────

:summary
echo.
echo ==================================================
set /a TOTAL=PASS+FAIL
echo   RESULTADO: %PASS%/%TOTAL% tests pasaron
if %FAIL%==0 (
    echo   CLUSTER OPERATIVO AL 100%% [%PROFILE%]
) else (
    echo   ATENCION: %FAIL% test(s) fallaron
)
echo ==================================================

:end
pause
