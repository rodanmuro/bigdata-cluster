FROM python:3.10-slim

# --- Evita prompts interactivos ---
ENV DEBIAN_FRONTEND=noninteractive

# --- Instala Java (JRE es suficiente para PySpark) ---
RUN apt-get update && apt-get install -y \
    openjdk-21-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# --- Configura JAVA_HOME ---
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# --- Directorio de trabajo ---
WORKDIR /app

# --- Instala PySpark y Jupyter (capa cacheada si no cambia) ---
RUN pip install --no-cache-dir pyspark==4.1.1 jupyter

# --- Puerto Jupyter ---
EXPOSE 8888

# --- Comando de inicio: Jupyter sin token ni password ---
CMD ["jupyter", "notebook", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--NotebookApp.token=''", "--NotebookApp.password=''"]
