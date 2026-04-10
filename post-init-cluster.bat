@echo off
setlocal enabledelayedexpansion

set PROFILE=%1
if "%PROFILE%"=="" set PROFILE=full

echo ========================================
echo  Inicializacion del Cluster - %PROFILE%
echo ========================================

if "%PROFILE%"=="hadoop"    goto do_hadoop
if "%PROFILE%"=="hive"      goto do_hive
if "%PROFILE%"=="spark"     goto do_spark
if "%PROFILE%"=="streaming" goto do_streaming
if "%PROFILE%"=="full"      goto do_full

echo.
echo Profile no reconocido: '%PROFILE%'
echo.
echo Uso: post-init-cluster.bat [profile]
echo.
echo Profiles disponibles:
echo   hadoop    - Solo inicializa directorios HDFS
echo   hive      - HDFS + metastore Hive + migraciones Hue
echo   spark     - Solo inicializa directorios HDFS
echo   streaming - HDFS + topics Kafka + JARs Flink + tablas PostgreSQL
echo   full      - Inicializacion completa (por defecto)
goto end

:do_hadoop
call :init_hadoop
goto done

:do_hive
call :init_hadoop
call :init_hive
call :init_hue
goto done

:do_spark
call :init_hadoop
goto done

:do_streaming
call :init_hadoop
call :init_streaming
goto done

:do_full
call :init_hadoop
call :init_hive
call :init_hue
call :init_streaming
goto done

:: ─── FUNCIONES ──────────────────────────────────

:init_hadoop
echo.
echo [HADOOP] Creando directorios en HDFS...
docker exec hadoop-namenode hdfs dfs -mkdir -p /user/admin
docker exec hadoop-namenode hdfs dfs -chown admin:admin /user/admin
docker exec hadoop-namenode hdfs dfs -mkdir -p /user/hive/warehouse
docker exec hadoop-namenode hdfs dfs -chown admin:admin /user/hive/warehouse
echo [HADOOP] Directorios creados.
goto :eof

:init_hive
echo.
echo [HIVE] Inicializando esquema del metastore...
docker exec hive-server /opt/hive/bin/schematool -initSchema -dbType hive -metaDbType postgres -url jdbc:hive2://localhost:10000/default
echo [HIVE] Metastore inicializado.
goto :eof

:init_hue
echo.
echo [HUE] Ejecutando migraciones de base de datos...
docker exec hue bash -c "cd /usr/share/hue && ./build/env/bin/hue migrate"
echo [HUE] Migraciones completadas.
goto :eof

:init_streaming
echo.
echo [KAFKA] Esperando a que el broker este listo...
set KAFKA_READY=0
for /l %%i in (1,1,20) do (
    if !KAFKA_READY!==0 (
        docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list >nul 2>&1
        if !errorlevel!==0 (
            set KAFKA_READY=1
        ) else (
            echo [KAFKA] Intento %%i/20 - esperando 5 segundos...
            timeout /t 5 /nobreak >nul
        )
    )
)

echo [KAFKA] Creando topics...
docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --create --if-not-exists --topic eventos-tienda --partitions 6 --replication-factor 1
docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --create --if-not-exists --topic metricas-procesadas --partitions 3 --replication-factor 1
echo [KAFKA] Topics creados.

echo.
echo [FLINK] Verificando JARs necesarios...
if not exist flink-jars mkdir flink-jars
set MAVEN=https://repo1.maven.org/maven2

if not exist "flink-jars\flink-sql-connector-kafka-3.3.0-1.19.jar" (
    echo [FLINK] Descargando flink-sql-connector-kafka...
    curl -fsSL -o "flink-jars\flink-sql-connector-kafka-3.3.0-1.19.jar" "%MAVEN%/org/apache/flink/flink-sql-connector-kafka/3.3.0-1.19/flink-sql-connector-kafka-3.3.0-1.19.jar"
) else (
    echo [FLINK] flink-sql-connector-kafka ya existe, omitiendo.
)

if not exist "flink-jars\flink-shaded-hadoop-2-uber-2.8.3-10.0.jar" (
    echo [FLINK] Descargando flink-shaded-hadoop-2-uber...
    curl -fsSL -o "flink-jars\flink-shaded-hadoop-2-uber-2.8.3-10.0.jar" "%MAVEN%/org/apache/flink/flink-shaded-hadoop-2-uber/2.8.3-10.0/flink-shaded-hadoop-2-uber-2.8.3-10.0.jar"
) else (
    echo [FLINK] flink-shaded-hadoop-2-uber ya existe, omitiendo.
)

if not exist "flink-jars\flink-connector-jdbc-3.2.0-1.19.jar" (
    echo [FLINK] Descargando flink-connector-jdbc...
    curl -fsSL -o "flink-jars\flink-connector-jdbc-3.2.0-1.19.jar" "%MAVEN%/org/apache/flink/flink-connector-jdbc/3.2.0-1.19/flink-connector-jdbc-3.2.0-1.19.jar"
) else (
    echo [FLINK] flink-connector-jdbc ya existe, omitiendo.
)
echo [FLINK] JARs listos.

echo.
echo [POSTGRES-STREAMING] Esperando a que PostgreSQL este listo...
set PG_READY=0
for /l %%i in (1,1,20) do (
    if !PG_READY!==0 (
        docker exec postgres-streaming pg_isready -U flink >nul 2>&1
        if !errorlevel!==0 (
            set PG_READY=1
        ) else (
            echo [POSTGRES-STREAMING] Intento %%i/20 - esperando 3 segundos...
            timeout /t 3 /nobreak >nul
        )
    )
)

echo [POSTGRES-STREAMING] Creando tablas...
docker exec postgres-streaming psql -U flink -d streaming -c "CREATE TABLE IF NOT EXISTS ventas_por_minuto (product_id VARCHAR(50), product VARCHAR(100), total_compras BIGINT, revenue DOUBLE PRECISION, ventana_inicio TIMESTAMP, ventana_fin TIMESTAMP, PRIMARY KEY (product_id, ventana_inicio));"
docker exec postgres-streaming psql -U flink -d streaming -c "CREATE TABLE IF NOT EXISTS eventos_por_tipo (tipo VARCHAR(50), total_eventos BIGINT, ventana_inicio TIMESTAMP, ventana_fin TIMESTAMP, PRIMARY KEY (tipo, ventana_inicio));"
echo [POSTGRES-STREAMING] Tablas creadas.

echo.
echo [FLINK] Reiniciando Flink para cargar los JARs descargados...
docker restart flink-jobmanager flink-taskmanager

echo [FLINK] Esperando a que el JobManager este listo...
set FLINK_READY=0
for /l %%i in (1,1,20) do (
    if !FLINK_READY!==0 (
        curl -s http://localhost:8085/overview >nul 2>&1
        if !errorlevel!==0 (
            set FLINK_READY=1
        ) else (
            echo [FLINK] Intento %%i/20 - esperando 5 segundos...
            timeout /t 5 /nobreak >nul
        )
    )
)

echo [FLINK] Creando directorio de checkpoints en HDFS...
docker exec hadoop-namenode hdfs dfs -mkdir -p /flink/checkpoints
docker exec hadoop-namenode hdfs dfs -mkdir -p /flink/savepoints

echo [FLINK] Enviando jobs SQL...
docker exec flink-jobmanager ./bin/sql-client.sh -f /opt/flink/jobs/ventas_por_minuto.sql
docker exec flink-jobmanager ./bin/sql-client.sh -f /opt/flink/jobs/eventos_por_tipo.sql
echo [FLINK] Jobs enviados.

echo.
echo [GRAFANA] Esperando a que Grafana este listo...
set GRAFANA_READY=0
for /l %%i in (1,1,20) do (
    if !GRAFANA_READY!==0 (
        curl -s http://localhost:3000/api/health | find "ok" >nul 2>&1
        if !errorlevel!==0 (
            set GRAFANA_READY=1
        ) else (
            echo [GRAFANA] Intento %%i/20 - esperando 5 segundos...
            timeout /t 5 /nobreak >nul
        )
    )
)
echo [GRAFANA] Grafana listo - dashboard disponible en http://localhost:3000
echo [GRAFANA] Credenciales: admin / admin
goto :eof

:done
echo.
echo ========================================
echo  Inicializacion completada: %PROFILE%
echo ========================================
echo.
echo Nota: si algun paso fallo por conexion, espera
echo unos segundos y vuelve a ejecutar el script.

:end
pause
