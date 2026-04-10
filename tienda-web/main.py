from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from confluent_kafka import Producer
from datetime import datetime, timezone
import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

producer = Producer({"bootstrap.servers": "kafka:9092"})


def delivery_report(err, msg):
    if err:
        logger.error(f"Error al enviar evento: {err}")


@app.post("/api/evento")
async def recibir_evento(request: Request):
    try:
        evento = await request.json()
    except Exception:
        return JSONResponse({"ok": False, "error": "JSON inválido"}, status_code=400)

    # Enriquecer con datos del servidor
    evento["timestamp"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    evento["ip"] = request.headers.get("x-forwarded-for", request.client.host)

    user_id = evento.get("user_id", "anonymous")

    producer.produce(
        "eventos-tienda",
        key=user_id,
        value=json.dumps(evento, ensure_ascii=False),
        callback=delivery_report,
    )
    producer.poll(0)

    return {"ok": True}


app.mount("/", StaticFiles(directory="static", html=True), name="static")
