@echo off
setlocal enabledelayedexpansion

set PROFILE=%1
if "%PROFILE%"=="" set PROFILE=full

echo ========================================
echo  Inicializacion del Cluster - %PROFILE%
echo ========================================

if "%PROFILE%"=="hadoop" goto do_hadoop
if "%PROFILE%"=="hive"   goto do_hive
if "%PROFILE%"=="spark"  goto do_spark
if "%PROFILE%"=="full"   goto do_full

echo.
echo Profile no reconocido: '%PROFILE%'
echo.
echo Uso: post-init-cluster.bat [profile]
echo.
echo Profiles disponibles:
echo   hadoop  - Solo inicializa directorios HDFS
echo   hive    - HDFS + metastore Hive + migraciones Hue
echo   spark   - Solo inicializa directorios HDFS
echo   full    - Inicializacion completa (por defecto)
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

:do_full
call :init_hadoop
call :init_hive
call :init_hue
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
