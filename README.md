# Guía para Levantar un Clúster Big Data con Docker Compose

Este repositorio contiene un conjunto de servicios orquestados con Docker Compose para levantar un clúster de Big Data compuesto por Hadoop, Hive, Hue, Spark, Jupyter, Superset y PostgreSQL.

---

## Espacio en Disco Requerido

> **Importante:** Antes de iniciar, asegúrate de tener suficiente espacio disponible en disco.

| Imagen | Tamaño aproximado |
| ---------------------------------- | ----------------- |
| `apache/hadoop:3.4.1`              | 2.1 GB            |
| `gethue/hue:latest`                | 2.6 GB            |
| `apache/hive:4.0.1`                | 1.6 GB            |
| `apache/spark:4.1.1`               | 1.3 GB            |
| `apache/superset:6.1.0rc1`         | 1.0 GB            |
| `postgres:14`                      | 0.4 GB            |
| `python-pyspark4-jupyter` (local)  | ~1.1 GB           |
| **Total estimado**                 | **~10 GB**        |

> **¿Por qué no se multiplica el espacio?** Docker usa un sistema de capas. Si hay 3 contenedores Spark, la imagen se descarga una sola vez (~1.3 GB), no tres veces. El espacio adicional por contenedor en ejecución es mínimo (unos pocos MB por logs y datos temporales).

---

## Requisitos Previos

* Docker y Docker Compose instalados
* Mínimo **10 GB** de espacio libre en disco
* Mínimo **8 GB de RAM** recomendados (el clúster levanta ~13 contenedores simultáneamente)
* Maven (solo si vas a reconstruir los jars de Hive desde fuentes)

---

## Versiones del Clúster

Las versiones están **fijadas intencionalmente** para garantizar compatibilidad entre servicios. Cambiarlas sin entender las dependencias puede romper la integración.

| Servicio | Versión |
| -------- | ------- |
| Apache Hadoop | 3.4.1 |
| Apache Hive | 4.0.1 |
| Apache Spark | 4.1.1 |
| PySpark | 4.1.1 |
| Python (contenedor Jupyter) | 3.10 |
| PostgreSQL | 14 |
| Hue | 4.11.0 |
| Apache Superset | 6.1.0rc1 |

> **Regla crítica de compatibilidad:** La versión de PySpark debe coincidir **exactamente** con la versión del clúster Spark, y Python debe ser la misma versión que tienen los workers de Spark. Ver sección de [Problemas de compatibilidad de versiones](#problemas-de-compatibilidad-de-versiones) para más detalles.

---

## Pasos para Inicializar el Clúster

### 1. Construir la imagen de PySpark + Jupyter

Este paso es **obligatorio**. La imagen se construye localmente porque requiere versiones específicas de Python y PySpark compatibles con el clúster Spark.

```bash
docker build -t python-pyspark4-jupyter .
```

> Este proceso puede tardar entre 5 y 10 minutos dependiendo de la velocidad de conexión a internet. Descarga Python 3.10-slim, Java 21 JRE y PySpark 4.1.1.

### 2. Levantar los servicios

```bash
docker compose up
```

> Se recomienda **no usar `-d`** (modo detach) para ver los logs en tiempo real y observar el proceso de arranque de cada servicio. Cuando Superset termine de inicializarse (el servicio más lento), aparecerá el siguiente mensaje en los logs:
>
> ```
> superset  | ╔══════════════════════════════════════════════════╗
> superset  | ║       CLUSTER BIG DATA LEVANTADO                 ║
> superset  | ╠══════════════════════════════════════════════════╣
> superset  | ║  Hadoop NameNode   →  http://localhost:9870       ║
> superset  | ║  Hadoop DataNode 1 →  http://localhost:9864       ║
> superset  | ║  Hadoop DataNode 2 →  http://localhost:9865       ║
> superset  | ║  Hive Web UI       →  http://localhost:10002      ║
> superset  | ║  Hue               →  http://localhost:8888       ║
> superset  | ║  Spark Master      →  http://localhost:8081       ║
> superset  | ║  Jupyter Notebook  →  http://localhost:8084       ║
> superset  | ║  Superset          →  http://localhost:8088       ║
> superset  | ╚══════════════════════════════════════════════════╝
> ```

### 3. Ejecutar el script de inicialización

Una vez todos los servicios estén corriendo, ejecutar **en otra terminal**:

```bash
# Linux / Mac
./post-init-cluster.sh

# Windows
post-init-cluster.bat
```

Este script realiza tres tareas esenciales:
1. **Crea directorios en HDFS** (`/user/admin`, `/user/hive/warehouse`) necesarios para que Hive pueda almacenar datos
2. **Inicializa el esquema del metastore de Hive** en PostgreSQL
3. **Aplica las migraciones de Hue** para crear las tablas de su base de datos

> **Nota:** Si el script falla por conexión, espera unos segundos y vuelve a ejecutarlo. Algunos servicios como Hive pueden tardar más en estar completamente listos.

> **Importante:** Este script debe ejecutarse **solo una vez** en el primer arranque, o cada vez que se haga `docker compose down -v` (que elimina los volúmenes y borra los datos).

### 4. Verificar que el clúster funciona correctamente

```bash
# Linux / Mac
./test-cluster.sh

# Windows
test-cluster.bat
```

Deberías ver al final:
```
RESULTADO: 22/22 tests pasaron
CLUSTER OPERATIVO AL 100%
```

Si algún test falla, consulta la sección de [Solución de Problemas](#solución-de-problemas).

---

## Apagar el Clúster

```bash
# Apagar conservando los datos (recomendado)
docker compose down

# Apagar eliminando todos los datos (HDFS, metastore, Hue BD)
docker compose down -v
```

> Usar `down -v` cuando quieras empezar desde cero. Recuerda ejecutar `post-init-cluster` nuevamente después.

---

## Puertos Expuestos en el Host

| Servicio           | Puerto | URL                        | Credenciales   |
| ------------------ | ------ | -------------------------- | -------------- |
| NameNode           | 9870   | http://localhost:9870      | -              |
| DataNode 1         | 9864   | http://localhost:9864      | -              |
| DataNode 2         | 9865   | http://localhost:9865      | -              |
| Hive Web UI        | 10002  | http://localhost:10002     | -              |
| Hue                | 8888   | http://localhost:8888      | admin / admin  |
| Spark Master       | 8081   | http://localhost:8081      | -              |
| Spark Worker 1     | 8082   | http://localhost:8082      | -              |
| Spark Worker 2     | 8083   | http://localhost:8083      | -              |
| Jupyter Notebook   | 8084   | http://localhost:8084      | sin token      |
| Apache Superset    | 8088   | http://localhost:8088      | admin / admin  |

---

## Estructura del Proyecto

```
bigdata-cluster/
├── hadoop-config/
│   ├── core-site.xml          # Configuración del sistema de archivos HDFS
│   └── hdfs-site.xml          # Configuración de replicación y DataNodes
├── hive-config/
│   └── hive-site.xml          # Configuración del metastore de Hive
├── hue-config/
│   └── hue.ini                # Configuración de Hue (conexión a Hive y PostgreSQL)
├── postgres-driver/
│   └── postgresql-42.7.6.jar  # Driver JDBC para conectar Hive con PostgreSQL
├── docker-compose.yml         # Definición de todos los servicios
├── Dockerfile                 # Imagen personalizada PySpark + Jupyter
├── post-init-cluster.sh       # Script de inicialización (Linux/Mac)
├── post-init-cluster.bat      # Script de inicialización (Windows)
├── test-cluster.sh            # Pruebas de integración (Linux/Mac)
├── test-cluster.bat           # Pruebas de integración (Windows)
├── superset_config.py         # Configuración adicional de Superset
└── README.md
```

---

## Servicios y Configuraciones

### PySpark + Jupyter

* Imagen construida localmente desde el `Dockerfile` con:
  * **Python 3.10** — debe coincidir con la versión de Python en los workers de Spark
  * **Java 21 JRE** — suficiente para ejecutar Spark (no se necesita el JDK completo)
  * **PySpark 4.1.1** — debe coincidir exactamente con la versión del clúster Spark
* Acceso sin token ni contraseña: `http://localhost:8084`

Para conectar PySpark al clúster Spark desde un notebook, usar **siempre** esta configuración:

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("mi-aplicacion") \
    .master("spark://spark-master:7077") \
    .config("spark.driver.host", "python-pyspark4-jupyter") \
    .config("spark.driver.bindAddress", "0.0.0.0") \
    .config("spark.driver.port", "7078") \
    .config("spark.blockManager.port", "7079") \
    .getOrCreate()
```

> **¿Por qué son necesarios esos parámetros?**
> En un clúster Spark distribuido, los workers necesitan saber la dirección del driver (el notebook) para devolver los resultados de los jobs. Sin `spark.driver.host`, los workers no pueden conectarse de vuelta al driver y el job se cuelga indefinidamente sin mostrar errores claros.

### Hadoop (NameNode y DataNodes)

* Versión: Hadoop **3.4.1**
* Arquitectura: 1 NameNode + 2 DataNodes
* Archivos de configuración requeridos:
  * `core-site.xml` — define la dirección del NameNode (`hdfs://hadoop-namenode:9000`)
  * `hdfs-site.xml` — define el factor de replicación y rutas de almacenamiento

* El NameNode formatea HDFS **solo si no existe data previa**. Esto evita el problema de desincronización de `clusterID` en reinicios:

```bash
# Lógica implementada en docker-compose.yml
[ -d /opt/hadoop/etc/hadoop/dfs/name/current ] || hdfs namenode -format && hdfs namenode
```

* Permisos HDFS desactivados (`dfs.permissions=false`) para permitir que Hive escriba sin restricciones — **solo apropiado en entorno académico**.

### Hive

* Tres contenedores que trabajan juntos:
  * `hive-server` — recibe y ejecuta queries HiveQL (puerto 10000 JDBC, 10002 Web UI)
  * `metastore` — servicio que guarda el esquema de las tablas
  * `postgres-metastore` — base de datos PostgreSQL donde se almacena el metastore

* Driver PostgreSQL mapeado a `/opt/hive/lib/postgres.jar`
* El `postgres.jar` proviene del [repositorio oficial JDBC](https://jdbc.postgresql.org/download.html) y tiene licencia BSD.
* Inicialización del metastore basada en la [documentación oficial de Apache Hive](https://github.com/apache/hive/tree/master/packaging/src/docker)
* El `hive-server` limpia automáticamente el archivo PID al arrancar para evitar el error `HiveServer2 running as process X` en reinicios.

### Hue

* Interfaz web para interactuar con el clúster sin usar la terminal:
  * Editor SQL con autocompletado para Hive
  * Explorador visual de archivos en HDFS
  * Historial de queries ejecutadas
* Usa PostgreSQL propio (`postgres-hue`) en lugar de SQLite para mayor estabilidad
* Credenciales: `admin` / `admin`
* Configuraciones esenciales en `hue-config/hue.ini`:

```ini
[beeswax]
hive_server_host=hive-server
hive_server_port=10000

[database]
engine=postgresql_psycopg2
host=postgres-hue
port=5432
user=hue
password=hue
name=hue
```

* Las migraciones de base de datos se ejecutan con `post-init-cluster`:

```bash
./build/env/bin/hue migrate
```

### Apache Spark

* Versión: **4.1.1**
* Arquitectura standalone: 1 Master + 2 Workers
* El Master gestiona los recursos y asigna jobs a los Workers
* Cada Worker expone su propia interfaz web (puertos 8082 y 8083)
* Se conecta a HDFS mediante `core-site.xml` montado en `/opt/spark/conf/`

### Apache Superset

* Plataforma de Business Intelligence para crear dashboards y visualizaciones sobre los datos de Hive
* Credenciales: `admin` / `admin`
* Para conectar a Hive ir a **Settings → Database Connections → + Database** y usar la URI:

```
hive://hive@hive-server:10000/default
```

> **Nota técnica importante:** Superset corre dentro de un virtualenv en `/app/.venv`. Los drivers de Hive (`pyhive`, `thrift`, `sasl`, `thrift-sasl`) se instalan automáticamente en ese virtualenv al arrancar el contenedor. Si ves el error `Could not load database driver: HiveEngineSpec`, verifica que el contenedor de Superset terminó su inicialización completa (puede tardar varios minutos la primera vez).

### Conexión a AWS S3

1. Crear bucket con permisos públicos:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPublicReadAndList",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::mibucketnombre",
        "arn:aws:s3:::mibucketnombre/*"
      ]
    }
  ]
}
```

2. Crear carpeta como `data/` dentro del bucket y subir archivos.
3. Los jars de AWS (`hadoop-aws-3.3.6.jar` y `aws-java-sdk-bundle-1.12.367.jar`) ya están enlazados automáticamente en el `docker-compose.yml` al arrancar Hive.
4. Crear tabla externa en Hive desde Hue:

```sql
CREATE EXTERNAL TABLE propiedades (
  frente INT,
  profundidad INT,
  precio INT
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3a://mibucket/data/'
TBLPROPERTIES ('skip.header.line.count'='1');
```

---

## Script post-init-cluster

Debe ejecutarse **una sola vez** después del primer `docker compose up`, o cada vez que se eliminen los volúmenes con `docker compose down -v`.

* Crea carpetas en HDFS (`/user/admin`, `/user/hive/warehouse`)
* Inicializa el metastore de Hive en PostgreSQL
* Ejecuta migraciones de Hue

**Nota:** Si el script falla por conexión, espera unos segundos y vuelve a ejecutarlo.

---

## Script de Pruebas de Integración

Los scripts `test-cluster.sh` (Linux/Mac) y `test-cluster.bat` (Windows) verifican automáticamente que todos los servicios están operativos y se comunican correctamente entre sí.

```bash
./test-cluster.sh
```

Pruebas incluidas:

| Módulo | Qué verifica |
|---|---|
| Servicios HTTP | Los 10 servicios responden con HTTP 200/302 |
| Hadoop / HDFS | DataNodes registrados, escritura y lectura de archivos |
| Hive | Conexión HiveServer2, CREATE/INSERT/SELECT/DROP completo |
| PySpark + Spark | Operación distribuida en workers, conectividad con HDFS |
| Hue | Login, acceso a HDFS, conectividad con HiveServer2 |
| Superset | Health check, autenticación JWT, driver pyhive disponible |

Salida esperada:
```
==================================================
  RESULTADO: 22/22 tests pasaron
  CLUSTER OPERATIVO AL 100%
==================================================
```

---

## Solución de Problemas

### Los DataNodes no arrancan (clusterID desincronizado)

**Síntoma:** En los logs del DataNode aparece:
```
All specified directories have failed to load
```

**Causa:** El NameNode fue reformateado generando un nuevo `clusterID`, pero los DataNodes conservan el `clusterID` anterior. No pueden sincronizarse.

**Solución:**
```bash
docker compose down -v
docker compose up
```
> El `-v` elimina los volúmenes y permite que todo arranque sincronizado. Ejecutar `post-init-cluster` nuevamente después.

---

### Hue muestra error 500 al iniciar

**Síntoma:** En los logs de Hue aparece:
```
django.db.utils.ProgrammingError: relation "desktop_settings" does not exist
```

**Causa:** Las migraciones de Hue no se aplicaron. Ocurre cuando se hace `docker compose down -v` y la base de datos de Hue queda vacía.

**Solución:**
```bash
docker exec hue bash -c "cd /usr/share/hue && ./build/env/bin/hue migrate"
```
O simplemente ejecutar de nuevo `post-init-cluster`.

---

### Superset no conecta a Hive (`Could not load database driver`)

**Síntoma:** Al agregar la conexión Hive en Superset aparece:
```
ERROR: Could not load database driver: HiveEngineSpec
```

**Causa:** El driver `pyhive` no está instalado en el virtualenv de Superset (`/app/.venv`). Superset corre en un virtualenv aislado y la instalación con `pip install` del sistema no lo alcanza.

**Solución temporal (en caliente):**
```bash
docker exec superset bash -c "/app/.venv/bin/python -m ensurepip && /app/.venv/bin/python -m pip install pyhive thrift sasl thrift-sasl"
```
> Esta instalación ya está incluida en el `docker-compose.yml` y se ejecuta automáticamente al arrancar.

---

### PySpark se cuelga al conectar al clúster Spark

**Síntoma:** El job nunca termina. En los logs de los workers aparece `KILLED exitStatus 143`.

**Causa:** Los workers de Spark pueden registrarse con el driver pero no pueden devolver resultados porque no saben a qué dirección/puerto conectarse.

**Solución:** Usar siempre la configuración completa del SparkSession con `spark.driver.host`, `spark.driver.port` y `spark.blockManager.port` (ver sección PySpark + Jupyter).

---

### Problemas de compatibilidad de versiones

Este es uno de los problemas más comunes al trabajar con clústeres Big Data en Docker.

**Regla fundamental:** PySpark debe tener **exactamente** la misma versión que Spark, y Python debe ser la misma versión en el driver (Jupyter) y los workers.

| Componente | Versión fijada | Consecuencia si no coincide |
|---|---|---|
| `apache/spark` | `4.1.1` | Workers no aceptan conexiones del driver |
| PySpark (Dockerfile) | `4.1.1` | Jobs fallan o se cuelgan |
| Python (Dockerfile) | `3.10` | Error de serialización (pickle) en lambdas |
| `apache/hadoop` | `3.4.1` | Incompatibilidad de APIs HDFS |
| `apache/hive` | `4.0.1` | Incompatibilidad con el metastore |
| `postgres` | `14` | Incompatibilidad de esquemas |

Si necesitas actualizar la versión de Spark, debes también actualizar PySpark en el Dockerfile y reconstruir la imagen:

```bash
# 1. Editar Dockerfile: cambiar pyspark==4.1.1 por la nueva versión
# 2. Editar docker-compose.yml: cambiar apache/spark:4.1.1 por la nueva versión
# 3. Eliminar imagen anterior
docker rmi python-pyspark4-jupyter
# 4. Reconstruir
docker build -t python-pyspark4-jupyter .
# 5. Reiniciar el clúster
docker compose down && docker compose up
```

---

## Consideraciones Finales

* Este entorno está diseñado con fines **académicos**.
* No recomendado para **producción** sin ajustes de seguridad adicionales.
* Contraseñas y configuraciones están simplificadas intencionalmente para facilitar el aprendizaje.
* El factor de replicación HDFS por defecto es 3, lo que requiere al menos 3 DataNodes en producción. En este entorno con 2 DataNodes es suficiente para pruebas.

---

## Recursos Recomendados

* Libro: *Big Data Analytics with Hadoop 3*
* Documentación oficial:
  * [Apache Hadoop](https://hadoop.apache.org/)
  * [Apache Hive](https://hive.apache.org/)
  * [Hue](https://gethue.com/)
  * [Apache Superset](https://superset.apache.org/)
  * [Apache Spark](https://spark.apache.org/)
  * [PySpark](https://spark.apache.org/docs/latest/api/python/)

---

> **Nota:** El archivo `postgres.jar` proviene del [repositorio oficial de PostgreSQL JDBC Driver](https://jdbc.postgresql.org/download.html) y se incluye para facilitar la integración con Hive. Se distribuye bajo licencia BSD.
