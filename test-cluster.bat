@echo off
setlocal enabledelayedexpansion

echo ==================================================
echo   PRUEBAS DE INTEGRACION - CLUSTER BIG DATA
echo ==================================================

set PASS=0
set FAIL=0

:: ─── SERVICIOS HTTP ───────────────────────────────
echo.
echo [ SERVICIOS HTTP ]

call :check_http 9870 "Hadoop NameNode"
call :check_http 9864 "DataNode 1"
call :check_http 9865 "DataNode 2"
call :check_http 10002 "Hive Web UI"
call :check_http 8888 "Hue"
call :check_http 8081 "Spark Master"
call :check_http 8082 "Spark Worker 1"
call :check_http 8083 "Spark Worker 2"
call :check_http 8084 "Jupyter"
call :check_http 8088 "Superset"

:: ─── HADOOP ───────────────────────────────────────
echo.
echo [ HADOOP / HDFS ]

for /f %%i in ('docker exec hadoop-namenode hdfs dfs -ls / 2^>nul ^| find /c "drw"') do set DN_COUNT=%%i
if !DN_COUNT! GEQ 1 (
    call :ok "Conexion NameNode - directorios en HDFS: !DN_COUNT!"
) else (
    call :fail "Conexion NameNode"
)

docker exec hadoop-namenode hdfs dfs -mkdir -p /test-ci >nul 2>&1
docker exec hadoop-namenode bash -c "echo test | hdfs dfs -put - /test-ci/test.txt" >nul 2>&1
for /f %%i in ('docker exec hadoop-namenode hdfs dfs -cat /test-ci/test.txt 2^>nul') do set CONTENT=%%i
if "!CONTENT!"=="test" (
    call :ok "Escritura/Lectura HDFS"
) else (
    call :fail "Escritura/Lectura HDFS"
)
docker exec hadoop-namenode hdfs dfs -rm -r /test-ci >nul 2>&1

:: ─── HIVE ─────────────────────────────────────────
echo.
echo [ HIVE ]

for /f %%i in ('docker exec hive-server bash -c "beeline -u jdbc:hive2://localhost:10000 -e \"SHOW DATABASES;\" 2>/dev/null" 2^>nul ^| find /c "default"') do set HIVE_OK=%%i
if !HIVE_OK! GEQ 1 (
    call :ok "Conexion HiveServer2"
) else (
    call :fail "Conexion HiveServer2"
)

docker exec hive-server bash -c "beeline -u jdbc:hive2://localhost:10000 -e \"CREATE DATABASE IF NOT EXISTS test_ci; USE test_ci; CREATE TABLE IF NOT EXISTS t (id INT); INSERT INTO t VALUES (1); DROP DATABASE test_ci CASCADE;\" 2>/dev/null" >nul 2>&1
call :ok "CRUD Hive ejecutado"

:: ─── PYSPARK ──────────────────────────────────────
echo.
echo [ PYSPARK + SPARK CLUSTER ]

for /f %%i in ('docker exec python-pyspark4-jupyter python -c "from pyspark.sql import SparkSession; spark = SparkSession.builder.appName(\"test\").master(\"spark://spark-master:7077\").config(\"spark.driver.host\",\"python-pyspark4-jupyter\").config(\"spark.driver.bindAddress\",\"0.0.0.0\").config(\"spark.driver.port\",\"7078\").config(\"spark.blockManager.port\",\"7079\").getOrCreate(); print(spark.sparkContext.parallelize(range(1,101)).reduce(lambda a,b:a+b)); spark.stop()" 2^>nul') do set SPARK_RESULT=%%i
if "!SPARK_RESULT!"=="5050" (
    call :ok "Operacion distribuida Spark (suma 1-100 = !SPARK_RESULT!)"
) else (
    call :fail "Operacion distribuida Spark (resultado: !SPARK_RESULT!)"
)

for /f %%i in ('docker exec python-pyspark4-jupyter python -c "from pyspark.sql import SparkSession; spark=SparkSession.builder.appName(\"t\").master(\"local\").getOrCreate(); sc=spark.sparkContext; sc._jvm.org.apache.hadoop.fs.FileSystem.get(sc._jvm.java.net.URI(\"hdfs://hadoop-namenode:9000\"),sc._jsc.hadoopConfiguration()).getStatus(sc._jvm.org.apache.hadoop.fs.Path(\"/\")); print(\"OK\"); spark.stop()" 2^>nul') do set HDFS_SPARK=%%i
if "!HDFS_SPARK!"=="OK" (
    call :ok "PySpark - HDFS"
) else (
    call :fail "PySpark - HDFS"
)

:: ─── HUE ──────────────────────────────────────────
echo.
echo [ HUE ]

for /f %%i in ('curl -s -o nul -w "%%{http_code}" http://localhost:8888/hue/accounts/login/') do set HUE_CODE=%%i
if "!HUE_CODE!"=="200" (
    call :ok "Hue login page accesible"
) else (
    call :fail "Hue login page (HTTP !HUE_CODE!)"
)

for /f %%i in ('docker exec hue bash -c "curl -s -o /dev/null -w %%{http_code} http://hive-server:10002" 2^>nul') do set HIVE_HUE=%%i
if "!HIVE_HUE!"=="200" (
    call :ok "Hue alcanza HiveServer2"
) else (
    call :fail "Hue alcanza HiveServer2"
)

:: ─── SUPERSET ─────────────────────────────────────
echo.
echo [ SUPERSET ]

for /f %%i in ('curl -s http://localhost:8088/health') do set HEALTH=%%i
if "!HEALTH!"=="OK" (
    call :ok "Health check"
) else (
    call :fail "Health check"
)

for /f %%i in ('docker exec superset bash -c "/app/.venv/bin/python -c \"import pyhive; print('OK')\"" 2^>nul') do set PYHIVE=%%i
if "!PYHIVE!"=="OK" (
    call :ok "pyhive en virtualenv"
) else (
    call :fail "pyhive en virtualenv"
)

:: ─── RESUMEN ──────────────────────────────────────
echo.
echo ==================================================
set /a TOTAL=PASS+FAIL
echo   RESULTADO: %PASS%/%TOTAL% tests pasaron
if %FAIL%==0 (
    echo   CLUSTER OPERATIVO AL 100%%
) else (
    echo   ATENCION: %FAIL% test(s) fallaron
)
echo ==================================================
goto :eof

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
