@echo off

echo ========================================
echo  Apagando el Cluster Big Data
echo ========================================

if "%1"=="-v" (
    echo.
    echo Modo limpieza: se eliminaran todos los volumenes ^(datos^).
    docker compose --profile full down -v
    echo.
    echo Cluster apagado y datos eliminados.
    echo Recuerda ejecutar post-init-cluster al volver a levantar.
) else (
    docker compose --profile full down
    echo.
    echo Cluster apagado. Los datos se conservaron.
    echo Para eliminar tambien los datos: stop-cluster.bat -v
)

echo ========================================
pause
