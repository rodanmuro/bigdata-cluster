# Guía para Levantar un Clúster Big Data con Docker Compose

Este repositorio contiene un conjunto de servicios orquestados con Docker Compose para levantar un clúster de Big Data compuesto por Hadoop, Hive, Hue, Spark, Jupyter, Superset, Kafka, Flink y PostgreSQL. Cubre tanto procesamiento **batch** (Hadoop, Hive, Spark) como procesamiento **en tiempo real** (Kafka, Flink).

---

## Espacio en Disco Requerido

> **Importante:** Antes de iniciar, asegúrate de tener suficiente espacio disponible en disco.

| Imagen | Tamaño real |
| ---------------------------------- | ----------- |
| `gethue/hue:latest`                | 2.61 GB     |
| `apache/hadoop:3.4.1`              | 2.08 GB     |
| `apache/hive:4.0.1`                | 1.60 GB     |
| `apache/spark:4.1.1`               | 1.33 GB     |
| `python-pyspark4-jupyter` (local)  | 1.11 GB     |
| `apache/superset:6.1.0rc1`         | 0.87 GB     |
| `apache/flink:1.19.0-scala_2.12`   | 0.80 GB     |
| `postgres:14`                      | 0.44 GB     |
| `grafana/grafana:11.0.0`           | 0.44 GB     |
| `apache/kafka:3.7.0`               | 0.39 GB     |
| `provectuslabs/kafka-ui:v0.7.2`    | 0.29 GB     |
| `python:3.11-slim` (tienda web)    | 0.12 GB     |
| **Total**                          | **~12 GB**  |

Uso total en disco con el profile `full` activo (medido con `docker system df`):

| Concepto | Tamaño |
|----------|-------:|
| Imágenes | 11.92 GB |
| Contenedores (logs + capas de escritura) | 1.95 GB |
| Volúmenes (HDFS, PostgreSQL, datos) | 2.43 GB |
| Build cache (imagen Jupyter) | 0.98 GB |
| **Total** | **~17.3 GB** |

> **¿Por qué no se multiplica el espacio?** Docker usa un sistema de capas. Si hay 3 contenedores Spark, la imagen se descarga una sola vez (~1.3 GB), no tres veces. El espacio adicional por contenedor en ejecución es mínimo (unos pocos MB por logs y datos temporales).

---

## Consumo de RAM por Contenedor

Mediciones reales con el profile `streaming` activo (10 contenedores, 4 jobs de Flink corriendo, tienda web activa):

| Contenedor | RAM en uso |
| ------------------- | ---------- |
| `flink-taskmanager` | 615 MB     |
| `flink-jobmanager`  | 547 MB     |
| `kafka`             | 411 MB     |
| `hadoop-namenode`   | 389 MB     |
| `hadoop-datanode-1` | 317 MB     |
| `kafka-ui`          | 307 MB     |
| `hadoop-datanode-2` | 278 MB     |
| `grafana`           | 75 MB      |
| `postgres-streaming`| 38 MB      |
| `tienda-web`        | 38 MB      |
| **Total**           | **~3.01 GB** |

> El profile `streaming` consume ~3 GB de RAM reales con los 4 jobs de Flink activos y la tienda web corriendo.

Mediciones reales con el profile `full` activo (20 contenedores):

| Contenedor | RAM en uso |
| -------------------------- | ---------- |
| `hive-server`              | 768 MB     |
| `metastore`                | 568 MB     |
| `flink-taskmanager`        | 554 MB     |
| `superset`                 | 536 MB     |
| `flink-jobmanager`         | 441 MB     |
| `hadoop-namenode`          | 437 MB     |
| `hue`                      | 336 MB     |
| `kafka`                    | 337 MB     |
| `hadoop-datanode-2`        | 309 MB     |
| `hadoop-datanode-1`        | 307 MB     |
| `kafka-ui`                 | 280 MB     |
| `spark-master`             | 218 MB     |
| `spark-worker-1`           | 217 MB     |
| `spark-worker-2`           | 214 MB     |
| `grafana`                  | 78 MB      |
| `postgres-metastore`       | 74 MB      |
| `tienda-web`               | 45 MB      |
| `postgres-hue`             | 36 MB      |
| `postgres-streaming`       | 28 MB      |
| `python-pyspark4-jupyter`  | 130 MB     |
| **Total**                  | **~5.9 GB** |

> El profile `full` consume ~5.9 GB de RAM reales con todos los servicios activos.

---

## Requisitos Previos

* Docker y Docker Compose instalados
* Mínimo **10 GB** de espacio libre en disco
* Mínimo **8 GB de RAM** para los profiles `hadoop`, `hive` y `spark`
* Mínimo **6 GB de RAM** para el profile `streaming` (~3 GB medidos en uso real)
* Mínimo **8 GB de RAM** para el profile `full` (~5.9 GB medidos en uso real)
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
| Apache Kafka | 3.7.0 |
| Kafka UI | 0.7.2 |
| Apache Flink | 1.19.0 |
| Grafana | 11.0.0 |
| Tienda Web (FastAPI) | 0.115.0 |
| Python (tienda web) | 3.11 |

> **Regla crítica de compatibilidad:** La versión de PySpark debe coincidir **exactamente** con la versión del clúster Spark, y Python debe ser la misma versión que tienen los workers de Spark. Ver sección de [Problemas de compatibilidad de versiones](#problemas-de-compatibilidad-de-versiones) para más detalles.

---

## Profiles Disponibles

El clúster usa **Docker Compose profiles** para permitir levantar solo los servicios que necesitas. Esto ahorra RAM y tiempo de arranque, y es útil para aprender cada componente de forma progresiva.

| Profile | Servicios incluidos | RAM medida |
|---------|--------------------|-----------:|
| `hadoop` | NameNode + 2 DataNodes | ~1.5 GB |
| `hive` | Hadoop + Metastore + HiveServer2 + Hue + PostgreSQL (x2) | ~4 GB |
| `spark` | Hadoop + Spark Master + 2 Workers + Jupyter | ~4 GB |
| `streaming` | Hadoop + Kafka + Kafka UI + Flink + PostgreSQL + Grafana + Tienda Web | ~3 GB |
| `full` | Todo lo anterior + Superset | ~5.9 GB |

> **Importante:** cada profile es **acumulativo** — el profile `hive` ya incluye Hadoop, no es necesario levantarlo por separado.

---

## Pasos para Inicializar el Clúster

### 1. Construir la imagen de PySpark + Jupyter

Este paso es **obligatorio** antes de usar los profiles `spark` o `full`. La imagen se construye localmente porque requiere versiones específicas de Python y PySpark compatibles con el clúster Spark.

```bash
docker build -t python-pyspark4-jupyter .
```

> Este proceso puede tardar entre 5 y 10 minutos dependiendo de la velocidad de conexión a internet. Descarga Python 3.10-slim, Java 21 JRE y PySpark 4.1.1.

### 2. Levantar los servicios

Elige el profile según lo que necesites:

```bash
# Solo Hadoop/HDFS
docker compose --profile hadoop up

# Hadoop + Hive + Hue
docker compose --profile hive up

# Hadoop + Spark + Jupyter
docker compose --profile spark up

# Hadoop + Kafka + Kafka UI
docker compose --profile streaming up

# Todo el clúster
docker compose --profile full up
```

> Cuando Superset termine de inicializarse (el servicio más lento del profile `full`), aparecerá el siguiente mensaje en los logs:
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

Una vez los servicios estén corriendo, ejecutar **en otra terminal** pasando el mismo profile:

```bash
# Linux / Mac
./post-init-cluster.sh hadoop
./post-init-cluster.sh hive
./post-init-cluster.sh spark
./post-init-cluster.sh streaming
./post-init-cluster.sh full   # por defecto si no se pasa argumento

# Windows
post-init-cluster.bat hadoop
post-init-cluster.bat hive
post-init-cluster.bat spark
post-init-cluster.bat streaming
post-init-cluster.bat full
```

Lo que hace cada profile:

| Profile | Acciones del script |
|---------|-------------------|
| `hadoop` | Crea directorios en HDFS (`/user/admin`, `/user/hive/warehouse`) |
| `hive` | Lo anterior + inicializa metastore de Hive + migraciones de Hue |
| `spark` | Crea directorios en HDFS |
| `streaming` | Crea directorios en HDFS + crea topics Kafka + descarga JARs de Flink + crea tablas en PostgreSQL + reinicia Flink para cargar JARs + envía jobs SQL automáticamente + espera a que Grafana esté listo |
| `full` | Todo lo de `hive` + todo lo de `streaming` |

> **Nota:** Si el script falla por conexión, espera unos segundos y vuelve a ejecutarlo. Algunos servicios como Hive pueden tardar más en estar completamente listos.

> **Importante:** Este script debe ejecutarse **solo una vez** en el primer arranque, o cada vez que se haga `docker compose down -v` (que elimina los volúmenes y borra los datos). Un `docker compose down` sin `-v` conserva los volúmenes y no requiere repetir el post-init.

### 4. Verificar que el clúster funciona correctamente

```bash
# Linux / Mac
./test-cluster.sh hadoop
./test-cluster.sh hive
./test-cluster.sh spark
./test-cluster.sh streaming
./test-cluster.sh full   # por defecto si no se pasa argumento

# Windows
test-cluster.bat hadoop
test-cluster.bat hive
test-cluster.bat spark
test-cluster.bat streaming
test-cluster.bat full
```

Deberías ver al final:
```
RESULTADO: X/X tests pasaron
CLUSTER OPERATIVO AL 100% [profile]
```

Si algún test falla, consulta la sección de [Solución de Problemas](#solución-de-problemas).

### 5. Cambiar de profile

Para cambiar de un profile a otro siempre usar `docker compose down` primero para eliminar los contenedores existentes:

```bash
./stop-cluster.sh
docker compose --profile spark up
```

> **¿Por qué es necesario el `down`?** Si un contenedor ya existe de una sesión anterior y simplemente se reinicia (sin recrear), puede quedar un archivo PID de Hive u otro estado residual que impide el arranque correcto. El `down` elimina los contenedores (no los volúmenes) y garantiza un arranque limpio.

---

## Apagar el Clúster

Usar siempre los scripts `stop-cluster` — funcionan sin importar con qué profile se levantó el clúster:

```bash
# Linux / Mac
./stop-cluster.sh       # apaga conservando los datos
./stop-cluster.sh -v    # apaga y elimina todos los datos

# Windows
stop-cluster.bat        # apaga conservando los datos
stop-cluster.bat -v     # apaga y elimina todos los datos
```

> **¿Por qué un script y no `docker compose down` directamente?** Los servicios tienen profiles definidos, y `docker compose down` sin especificar el profile correcto no encuentra los contenedores y sale silenciosamente sin hacer nada. El script usa `--profile full` internamente, que cubre todos los servicios sin excepción.

| Comando | Contenedores | Volúmenes (datos) | ¿Repetir post-init? |
|---------|:-----------:|:-----------------:|:-------------------:|
| `./stop-cluster.sh` | eliminados | conservados | No |
| `./stop-cluster.sh -v` | eliminados | eliminados | Sí |

### Eliminar todo rastro del clúster del sistema

**Si quieres eliminar todo — imágenes, volúmenes, datos y caché (~17 GB liberados):**

```bash
# 1. Bajar el clúster eliminando volúmenes
./stop-cluster.sh -v

# 2. Eliminar todas las imágenes
docker rmi apache/hadoop:3.4.1 apache/hive:4.0.1 apache/spark:4.1.1 \
           apache/kafka:3.7.0 apache/flink:1.19.0-scala_2.12 \
           provectuslabs/kafka-ui:v0.7.2 grafana/grafana:11.0.0 \
           gethue/hue:latest apache/superset:6.1.0rc1 \
           postgres:14 python:3.11-slim python-pyspark4-jupyter

# 3. Limpiar caché de build y volúmenes huérfanos
docker volume prune -f
docker builder prune -f
```

> El sistema queda como si nunca se hubiera instalado. Para volver a usarlo hay que descargar las imágenes nuevamente (~12 GB).

**Si quieres eliminar las imágenes pero conservar los datos (volúmenes):**

```bash
# 1. Bajar el clúster conservando volúmenes
./stop-cluster.sh

# 2. Eliminar las imágenes
docker rmi apache/hadoop:3.4.1 apache/hive:4.0.1 apache/spark:4.1.1 \
           apache/kafka:3.7.0 apache/flink:1.19.0-scala_2.12 \
           provectuslabs/kafka-ui:v0.7.2 grafana/grafana:11.0.0 \
           gethue/hue:latest apache/superset:6.1.0rc1 \
           postgres:14 python:3.11-slim python-pyspark4-jupyter
```

> Los datos de HDFS y PostgreSQL se conservan en los volúmenes Docker. Cuando vuelvas a levantar el clúster, no será necesario ejecutar `post-init-cluster` de nuevo.

---

## Puertos Expuestos en el Host

| Servicio           | Profile              | Puerto | URL                        | Credenciales   |
| ------------------ | -------------------- | ------ | -------------------------- | -------------- |
| NameNode           | todos                | 9870   | http://localhost:9870      | -              |
| DataNode 1         | todos                | 9864   | http://localhost:9864      | -              |
| DataNode 2         | todos                | 9865   | http://localhost:9865      | -              |
| Hive Web UI        | hive, full           | 10002  | http://localhost:10002     | -              |
| Hue                | hive, full           | 8888   | http://localhost:8888      | admin / admin  |
| Spark Master       | spark, full          | 8081   | http://localhost:8081      | -              |
| Spark Worker 1     | spark, full          | 8082   | http://localhost:8082      | -              |
| Spark Worker 2     | spark, full          | 8083   | http://localhost:8083      | -              |
| Jupyter Notebook   | spark, full          | 8084   | http://localhost:8084      | sin token      |
| Kafka broker       | streaming, full      | 9092   | -                          | -              |
| Kafka UI           | streaming, full      | 8090   | http://localhost:8090      | -              |
| Flink JobManager   | streaming, full      | 8085   | http://localhost:8085      | -              |
| PostgreSQL streaming | streaming, full    | 5545   | -                          | flink / flink  |
| Grafana            | streaming, full      | 3000   | http://localhost:3000      | admin / admin  |
| Tienda Web         | streaming, full      | 8091   | http://localhost:8091      | -              |
| Apache Superset    | full                 | 8088   | http://localhost:8088      | admin / admin  |

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
├── flink-config/
│   └── flink-conf.yaml        # Configuración de Flink (memoria, checkpointing, slots)
├── flink-jobs/
│   ├── ventas_por_minuto.sql      # Job SQL: revenue por producto (simulador + tienda)
│   ├── eventos_por_tipo.sql       # Job SQL: conteo de todos los tipos de evento
│   ├── actividad_productos.sql    # Job SQL: hover/carrito/compra por producto (solo tienda)
│   └── sesiones_navegadores.sql   # Job SQL: IP, browser y OS por sesión (solo tienda)
├── flink-jars/                # JARs de Flink (descargados por post-init, en .gitignore)
├── grafana-config/
│   ├── datasources/
│   │   └── postgres.yaml      # Conexión automática a PostgreSQL streaming
│   └── dashboards/
│       ├── dashboard.yaml     # Configuración del proveedor de dashboards
│       └── streaming.json     # Dashboard pre-construido de streaming
├── tienda-web/
│   ├── requirements.txt       # Dependencias Python (fastapi, uvicorn, confluent-kafka)
│   ├── main.py                # API FastAPI: POST /api/evento → Kafka
│   └── static/
│       └── index.html         # Tienda online (HTML + CSS + JS embebidos)
├── docker-compose.yml         # Definición de todos los servicios
├── Dockerfile                 # Imagen personalizada PySpark + Jupyter
├── .gitignore                 # Excluye flink-jars/*.jar del repositorio
├── post-init-cluster.sh       # Script de inicialización (Linux/Mac)
├── post-init-cluster.bat      # Script de inicialización (Windows)
├── stop-cluster.sh            # Script de apagado seguro (Linux/Mac)
├── stop-cluster.bat           # Script de apagado seguro (Windows)
├── test-cluster.sh            # Pruebas de integración (Linux/Mac)
├── test-cluster.bat           # Pruebas de integración (Windows)
├── simulador.py               # Generador de eventos de fondo para Kafka
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

### Apache Kafka

* Versión: **3.7.0** en modo **KRaft** (sin ZooKeeper — arquitectura simplificada)
* Un único broker que actúa también como controlador del clúster
* `CLUSTER_ID` fijo en el `docker-compose.yml` para garantizar reproducibilidad entre reinicios (un ID aleatorio rompería el estado al hacer `down` y `up`)
* Topics creados por `post-init-cluster`:

| Topic | Particiones | Descripción |
|-------|:-----------:|-------------|
| `eventos-tienda` | 6 | Eventos crudos del simulador (page_view, purchase, etc.) |
| `metricas-procesadas` | 3 | Resultados del procesamiento (uso futuro con Flink) |

* La creación automática de topics está **desactivada** (`KAFKA_AUTO_CREATE_TOPICS_ENABLE: "false"`) — los topics deben crearse explícitamente para que los estudiantes vean el proceso.

### Kafka UI

* Interfaz web para explorar el clúster Kafka sin usar la terminal:
  * Vista de topics, particiones y offsets
  * Explorador de mensajes con decodificación JSON
  * Consumer groups y lag monitoring
  * Posibilidad de producir mensajes manualmente desde el navegador
* Sin credenciales — acceso libre en entorno académico
* Acceso: `http://localhost:8090`

### Apache Flink

* Versión: **1.19.0** (Scala 2.12)
* Arquitectura: 1 JobManager + 1 TaskManager con 4 slots
* El JobManager coordina los jobs y gestiona el estado. El TaskManager ejecuta las tareas en paralelo.
* Checkpointing configurado en HDFS (`/flink/checkpoints`) para tolerancia a fallos — si Flink se reinicia, los jobs retoman desde el último checkpoint sin perder datos.
* Web UI de **monitoreo**: `http://localhost:8085` — permite ver jobs corriendo, métricas y logs, pero **no ejecutar SQL**.

**¿Cómo se programan los jobs en este clúster?**

Flink soporta varias formas de programarse (Java, Scala, Python/PyFlink), pero en este clúster se usa **Flink SQL** por ser la más legible para estudiantes con conocimientos de SQL.

Los jobs SQL se ejecutan desde la **terminal** usando el SQL Client incluido en la imagen de Flink. No se usa interfaz web para esto — la decisión es intencional para mantener el clúster simple y enfocado en el aprendizaje del pipeline de datos, no en herramientas adicionales.

```bash
# Abrir el SQL Client interactivo
docker exec -it flink-jobmanager ./bin/sql-client.sh

# Ejecutar un job SQL desde archivo (forma recomendada)
docker exec flink-jobmanager ./bin/sql-client.sh -f /opt/flink/jobs/ventas_por_minuto.sql
```

> **¿Por qué no hay interfaz web para SQL?** Existen herramientas como Apache Zeppelin que permiten ejecutar Flink SQL desde el navegador, pero agregan complejidad de configuración y más de 800 MB adicionales al clúster. Para el objetivo académico de este proyecto — entender el pipeline de streaming — la terminal es suficiente y más transparente.

**JARs adicionales** (descargados automáticamente por `post-init-cluster`):

| JAR | Función |
|-----|---------|
| `flink-sql-connector-kafka-3.3.0-1.19.jar` | Leer eventos desde Kafka |
| `flink-shaded-hadoop-2-uber-2.8.3-10.0.jar` | Escritura de checkpoints en HDFS |
| `flink-connector-jdbc-3.2.0-1.19.jar` | Escribir resultados en PostgreSQL |

> Los JARs se descargan en `flink-jars/` la primera vez que se ejecuta `post-init-cluster`. En ejecuciones posteriores se verifica si ya existen para no volver a descargarlos. La carpeta está en `.gitignore`.

**Jobs SQL incluidos** en `flink-jobs/`:

| Job | Fuente de datos | Descripción | Ventana |
|-----|----------------|-------------|---------|
| `ventas_por_minuto.sql` | Simulador + tienda | Revenue y compras por producto | 1 segundo |
| `eventos_por_tipo.sql` | Simulador + tienda | Conteo de todos los tipos de evento | 1 segundo |
| `actividad_productos.sql` | Solo tienda web | Hover, add_to_cart y purchase por producto | 1 segundo |
| `sesiones_navegadores.sql` | Solo tienda web | IP, browser y OS por sesión | 1 segundo |

Los jobs de la tienda web filtran `WHERE browser IS NOT NULL` para descartar silenciosamente los eventos del simulador (que no envían esos campos). Mientras corre el simulador esos paneles muestran "No data" — en cuanto los estudiantes abren la tienda web se llenan automáticamente.

Cada archivo SQL define tres cosas en orden:
1. **Tabla fuente** — cómo conectarse a Kafka y leer los mensajes
2. **Tabla destino** — cómo conectarse a PostgreSQL y escribir los resultados
3. **Job** — la lógica de transformación (filtros, agrupaciones, ventanas de tiempo)

> **Idle timeout:** todos los jobs tienen `'scan.watermark.idle-timeout' = '5 s'`. Esto garantiza que si no llegan eventos por 5 segundos, Flink avanza el watermark igualmente y cierra las ventanas pendientes. Sin esto, periodos de inactividad (por ejemplo, nadie navegando en la tienda) congelarían el pipeline.

### Grafana

* Versión: **11.0.0**
* Plataforma de visualización de datos en tiempo real
* Credenciales: `admin` / `admin`
* Acceso: `http://localhost:3000`

**Configuración automática por aprovisionamiento** — al arrancar el contenedor, Grafana carga automáticamente desde `grafana-config/`:

| Archivo | Qué configura |
|---------|--------------|
| `datasources/postgres.yaml` | Conexión a `postgres-streaming` (sin configuración manual) |
| `dashboards/dashboard.yaml` | Dónde buscar los archivos de dashboards |
| `dashboards/streaming.json` | Dashboard pre-construido listo para usar |

**Dashboard incluido: "Clúster Big Data — Streaming en Tiempo Real"**

Paneles activos con el simulador y con la tienda web:

| Panel | Tipo | Tabla PostgreSQL |
|-------|------|-----------------|
| Revenue por producto por minuto | Gráfico de líneas | `ventas_por_minuto` |
| Revenue total acumulado | Stat | `ventas_por_minuto` |
| Total de compras | Stat | `ventas_por_minuto` |
| Eventos por tipo (últimas ventanas) | Barras | `eventos_por_tipo` |
| Top productos por revenue | Tabla | `ventas_por_minuto` |
| Eventos por tipo en el tiempo | Gráfico de líneas | `eventos_por_tipo` |

Paneles que se activan solo con la tienda web (muestran "No data" con el simulador):

| Panel | Tipo | Tabla PostgreSQL |
|-------|------|-----------------|
| Funnel de conversión | Barras | `eventos_por_tipo` |
| Top productos más visitados (hover) | Barras | `actividad_productos` |
| Navegadores | Barras | `sesiones_navegadores` |
| Sistemas operativos | Barras | `sesiones_navegadores` |
| Estudiantes conectados (IP + browser + OS) | Tabla | `sesiones_navegadores` |

> El dashboard se refresca automáticamente cada **2 segundos** (configurable hasta 1s desde el selector de Grafana).

### Tienda Web (`tienda-web/`)

Aplicación web incluida en el clúster que simula una tienda en línea. Los estudiantes abren `http://localhost:8091` en su browser, navegan por el catálogo y cada interacción se registra automáticamente en Kafka, pasa por Flink y aparece en Grafana en tiempo real.

**Arquitectura:**

```
Browser del estudiante  →  FastAPI (puerto 8091)  →  Kafka (eventos-tienda)  →  Flink  →  PostgreSQL  →  Grafana
```

FastAPI sirve el frontend estático **y** expone el endpoint `/api/evento` que recibe los eventos del browser, los enriquece con IP y timestamp del servidor, y los publica en Kafka.

**Eventos capturados:**

| Evento | Cuándo se dispara |
|--------|------------------|
| `page_view` | Al abrir la página |
| `product_hover` | Al pasar el mouse sobre una tarjeta de producto |
| `add_to_cart` | Al hacer clic en "Agregar al carrito" |
| `purchase` | Al hacer clic en "Comprar" (finaliza el carrito completo) |
| `time_on_page` | Automáticamente cada 5 segundos mientras la página está abierta |

**Datos capturados por evento:**

- `product_id`, `product`, `category`, `price`, `quantity`, `total` — datos del producto
- `user_id` — ID de sesión único por tab del browser (se genera en `sessionStorage`)
- `browser` — Chrome, Firefox, Edge, Safari, etc. (detectado por JavaScript)
- `os` — Windows, MacOS, Linux, Android (detectado por JavaScript)
- `ip` — dirección IP real del cliente (capturada por FastAPI en el servidor)
- `timestamp` — fecha/hora UTC (asignada por el servidor, no por el browser)

**Sin Dockerfile:** la tienda usa la imagen oficial `python:3.11-slim`. Al arrancar, el contenedor instala las dependencias desde `requirements.txt` y lanza el servidor. Es consistente con el enfoque del resto del clúster — solo Docker Compose, sin imágenes personalizadas.

**Compatibilidad con los Flink jobs:** El esquema de eventos es el mismo que usa `simulador.py`. Los jobs SQL existentes (`ventas_por_minuto`, `eventos_por_tipo`) procesan los eventos de la tienda sin modificaciones. El panel de Grafana se actualiza en tiempo real con las compras y navegación de los estudiantes.

---

### Simulador de Eventos (`simulador.py`)

Script Python incluido en la raíz del proyecto que genera eventos continuos hacia Kafka, simulando el tráfico de una tienda en línea. Está diseñado para mantenerse corriendo indefinidamente hasta que se interrumpa con `Ctrl+C`.

**Eventos generados:**

| Tipo | Probabilidad | Descripción |
|------|:------------:|-------------|
| `page_view` | 35 % | Visita a la página de un producto |
| `purchase` | 30 % | Compra completada |
| `add_to_cart` | 20 % | Producto agregado al carrito |
| `cart_abandon` | 10 % | Abandono del carrito |
| `search` | 5 % | Búsqueda de producto |

Cada evento incluye: `type`, `product_id`, `product`, `category`, `price`, `quantity`, `total`, `user_id` y `timestamp` (ISO 8601). El `user_id` se usa como clave Kafka para que los eventos del mismo usuario siempre vayan a la misma partición.

**Requisito previo (solo la primera vez):**

```bash
pip install confluent-kafka
```

**Configurar resolución de hostname de Kafka:**

El simulador corre en el host (fuera de Docker), pero Kafka anuncia su hostname interno `kafka` a los clientes. Es necesario agregar una entrada en `/etc/hosts`:

```bash
# Linux / Mac — agregar esta línea a /etc/hosts
echo "127.0.0.1 kafka" | sudo tee -a /etc/hosts

# Windows — editar C:\Windows\System32\drivers\etc\hosts como administrador
# Agregar la línea:  127.0.0.1  kafka
```

**Ejecutar el simulador:**

```bash
python simulador.py
```

El simulador envía **3 eventos por segundo** por defecto. Mientras esté corriendo, Flink los procesa con ventanas de 1 segundo y escribe los resultados en PostgreSQL. Grafana los visualiza en tiempo real cada 2 segundos.

---

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

Debe ejecutarse **una sola vez** después del primer arranque, o cada vez que se eliminen los volúmenes con `docker compose down -v`. Acepta el mismo profile que usaste al levantar el clúster:

```bash
./post-init-cluster.sh streaming   # o hadoop, hive, spark, full
```

Acciones por profile:

| Profile | Qué hace |
|---------|----------|
| `hadoop` | Crea carpetas en HDFS (`/user/admin`, `/user/hive/warehouse`) |
| `hive` | Lo anterior + inicializa metastore de Hive + migraciones de Hue |
| `spark` | Crea carpetas en HDFS |
| `streaming` | Crea carpetas en HDFS + topics Kafka + descarga JARs de Flink + tablas PostgreSQL + reinicia Flink + envía jobs SQL + espera Grafana |
| `full` | Todo `hive` + todo `streaming` |

**Nota:** Si el script falla por conexión, espera unos segundos y vuelve a ejecutarlo.

---

## Script de Pruebas de Integración

Los scripts `test-cluster.sh` (Linux/Mac) y `test-cluster.bat` (Windows) verifican automáticamente que los servicios del profile activo están operativos y se comunican correctamente entre sí.

```bash
./test-cluster.sh hive   # o hadoop, spark, full
```

Pruebas incluidas por profile:

| Módulo | hadoop | hive | spark | streaming | full |
|--------|:------:|:----:|:-----:|:---------:|:----:|
| Hadoop / HDFS (HTTP + escritura/lectura) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Hive (HiveServer2 + CRUD completo) | | ✓ | | | ✓ |
| Hue (login + HDFS + conectividad Hive) | | ✓ | | | ✓ |
| Spark (HTTP + operación distribuida + HDFS) | | | ✓ | | ✓ |
| Kafka (broker + topics + produce/consume) | | | | ✓ | ✓ |
| Kafka UI (HTTP) | | | | ✓ | ✓ |
| Flink (JobManager + TaskManager + slots) | | | | ✓ | ✓ |
| PostgreSQL streaming (4 tablas) | | | | ✓ | ✓ |
| Tienda Web (HTTP + API /api/evento) | | | | ✓ | ✓ |
| Grafana (health + datasource + dashboard) | | | | ✓ | ✓ |
| Superset (health + pyhive) | | | | | ✓ |

Salida esperada:
```
==================================================
  RESULTADO: X/X tests pasaron
  CLUSTER OPERATIVO AL 100% [profile]
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

## Clúster Hadoop Distribuido en AWS (`aws-hadoop-cluster/`)

Además del clúster local con Docker Compose, el repositorio incluye scripts para desplegar un clúster Hadoop **real y distribuido en AWS EC2**: 3 instancias separadas (1 NameNode + 2 DataNodes), cada una con Docker. Está pensado para demostraciones en aula donde se quiere mostrar un entorno distribuido real sin infraestructura on-premise.

Todo el despliegue se automatiza con **AWS CLI** — no se requiere entrar a la consola web de AWS para ningún paso. Un solo script crea la red, las instancias, la configuración y devuelve las URLs listas para usar.

### Prerrequisitos

#### 1. Cuenta AWS con usuario IAM

No se puede usar la cuenta **root** de AWS directamente para este tipo de trabajo. La práctica recomendada es:

1. Entrar a la consola web de AWS con la cuenta root: `https://console.aws.amazon.com`
2. Ir a **IAM → Users → Create user**
3. Asignarle permisos de administrador (o al menos: EC2 full access)
4. El usuario IAM tiene su propia URL de acceso: `https://<account-id>.signin.aws.amazon.com/console`
5. Una vez creado el usuario, ir a **IAM → Users → tu-usuario → Security credentials → Create access key**
6. Guardar el **Access Key ID** y el **Secret Access Key** — solo se muestran una vez

#### 2. AWS CLI instalado en tu máquina

```bash
# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Mac
brew install awscli

# Windows
# Descargar el instalador desde: https://aws.amazon.com/cli/
```

#### 3. Configurar las credenciales localmente

```bash
aws configure
```

El comando pedirá:

```
AWS Access Key ID:     <tu Access Key ID del paso anterior>
AWS Secret Access Key: <tu Secret Access Key del paso anterior>
Default region name:   us-east-1
Default output format: json
```

Las credenciales se guardan en `~/.aws/credentials`. Para verificar que funcionan:

```bash
aws sts get-caller-identity
```

Si devuelve tu `Account`, `UserId` y `Arn`, está correctamente configurado.

### Arquitectura

```
Internet
    │
    ├── EC2 NameNode (t3.medium)   → Web UI: http://<IP>:9870
    │       └── hadoop-namenode (Docker)
    │
    ├── EC2 DataNode 1 (t3.medium) → Web UI: http://<IP>:9864
    │       └── hadoop-datanode (Docker)
    │
    └── EC2 DataNode 2 (t3.medium) → Web UI: http://<IP>:9864
            └── hadoop-datanode (Docker)
```

Los 3 nodos se comunican entre sí usando el **DNS interno de AWS** (`ip-X-X-X-X.ec2.internal`). El NameNode captura su propio DNS interno desde el servicio de metadatos de EC2 (`169.254.169.254`) al arrancar y lo escribe en `core-site.xml`. Los DataNodes reciben ese DNS en su `core-site.xml` al momento del despliegue. Así la comunicación intra-clúster usa red privada (sin coste de transferencia) y es estable sin necesidad de IPs elásticas.

### Scripts disponibles

```
aws-hadoop-cluster/
├── deploy.sh      # Despliega el clúster completo
├── teardown.sh    # Elimina todos los recursos AWS creados
└── status.sh      # Muestra el estado actual de las instancias
```

### Desplegar el clúster

```bash
cd aws-hadoop-cluster
bash deploy.sh
```

El script realiza automáticamente con AWS CLI:

1. Crea un **key pair** y guarda el `.pem` localmente
2. Busca el **AMI Ubuntu 22.04** más reciente en la región
3. Crea una **VPC** (10.0.0.0/16) con DNS hostnames habilitado, subnet en `us-east-1a`, Internet Gateway y route table
4. Crea un **security group** con los siguientes puertos abiertos:

| Puerto | Descripción |
|--------|-------------|
| 22 | SSH |
| 9870 | NameNode Web UI |
| 9864 | DataNode Web UI |
| 9866 | DataNode — transferencia de datos (upload desde browser) |
| Todos (intra-grupo) | Comunicación libre entre los 3 nodos |

5. Lanza el **NameNode** — su `user-data` instala Docker, genera `core-site.xml` con su propio DNS interno y arranca el contenedor
6. Espera a que el NameNode obtenga IP y DNS privado
7. Lanza los **2 DataNodes** con el DNS del NameNode ya escrito en su `core-site.xml`
8. Guarda todos los IDs de recursos en `cluster-state.env` para el teardown
9. Imprime las URLs y comandos SSH

Al terminar el deploy, el bootstrap de Docker sigue corriendo en las instancias en segundo plano (~3-5 minutos). Las interfaces web están disponibles cuando responden HTTP 302.

### Configuraciones clave aplicadas

| Problema | Solución |
|----------|----------|
| Hadoop no podía escribir en el volumen Docker | `user: "0:0"` en docker-compose + `mkdir -p` antes de arrancar |
| NameNode no podía hacer bind en el DNS de AWS desde dentro del contenedor | `dfs.namenode.rpc-bind-host=0.0.0.0` y `dfs.namenode.http-bind-host=0.0.0.0` en `hdfs-site.xml` |
| Browser no podía subir archivos (redirigía a IP interna del contenedor) | `dfs.datanode.hostname=<IP_PUBLICA>` obtenida del metadata de EC2, y `dfs.client.use.datanode.hostname=true` |
| Web UI mostraba "Permission denied: user=dr.who" | `hadoop.http.staticuser.user=hdfs` en `core-site.xml` |
| NameNode reformateaba en cada reinicio, desincronizando cluster IDs | Formato condicional: solo si no existe `/hadoop/dfs/name/current` |

### Usar el clúster

Una vez desplegado, la UI del NameNode permite explorar HDFS y subir archivos:

1. Ir a `http://<NameNode_IP>:9870`
2. **Utilities → Browse the file system**
3. Navegar a `/data` (carpeta creada con permisos abiertos por el script)
4. Usar el botón de subida para cargar archivos directamente desde el browser

Los DataNodes aparecen bajo **Datanodes** → "In service" (2 nodos). El factor de replicación es **2**: cada archivo se almacena una copia en cada DataNode.

> **Replicación = 2:** si subes un archivo de 200 MB, se consumen 400 MB del clúster (200 MB × 2 copias). La ventaja es tolerancia a fallos — si un DataNode cae, el archivo sigue disponible en el otro.

### Ver el estado

```bash
bash status.sh
```

Muestra el estado de cada instancia (running / stopped / terminated), IPs públicas actuales y URLs.

### Bajar el clúster

```bash
bash teardown.sh
```

Pide confirmación, luego elimina en orden: instancias EC2 → security group → IGW → subnet → VPC → key pair. El archivo `cluster-state.env` y el `.pem` local se eliminan automáticamente.

### Costo estimado

| Concepto | Costo |
|----------|------:|
| 3 × t3.medium (`us-east-1`) | ~$0.042/hora × 3 = ~$0.13/hora |
| EBS 8 GB × 3 instancias | ~$0.001/hora total |
| Transferencia de datos | despreciable en demo |
| **Total para una clase de 2 horas** | **< $0.30 USD** |

> Ejecutar `teardown.sh` al terminar la clase deja la cuenta completamente limpia sin cargos continuos.

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
  * [Apache Kafka](https://kafka.apache.org/)
  * [Apache Flink](https://flink.apache.org/)
  * [Flink SQL](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
  * [Grafana](https://grafana.com/docs/)

---

> **Nota:** El archivo `postgres.jar` proviene del [repositorio oficial de PostgreSQL JDBC Driver](https://jdbc.postgresql.org/download.html) y se incluye para facilitar la integración con Hive. Se distribuye bajo licencia BSD.
