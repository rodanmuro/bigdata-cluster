#!/usr/bin/env python3
"""
Simulador de eventos de tienda — Clúster Big Data
Genera eventos aleatorios y los envía a Kafka indefinidamente.
Ctrl+C para detener.
"""

import json
import random
import time
from datetime import datetime, timezone
from confluent_kafka import Producer

# ── Configuración ──────────────────────────────────────────────────
KAFKA_BROKER = "localhost:9092"
TOPIC        = "eventos-tienda"
EVENTOS_POR_SEGUNDO = 3   # ajustable

# ── Catálogo de productos ──────────────────────────────────────────
PRODUCTOS = [
    {"product_id": "P001", "product": "Laptop Pro",     "price": 1299, "category": "electronica"},
    {"product_id": "P002", "product": "Celular X",      "price": 799,  "category": "electronica"},
    {"product_id": "P003", "product": "Tablet Air",     "price": 499,  "category": "electronica"},
    {"product_id": "P004", "product": "Auriculares BT", "price": 149,  "category": "accesorios"},
    {"product_id": "P005", "product": "Monitor 4K",     "price": 899,  "category": "electronica"},
    {"product_id": "P006", "product": "Teclado RGB",    "price": 89,   "category": "accesorios"},
    {"product_id": "P007", "product": "Mouse Gamer",    "price": 59,   "category": "accesorios"},
]

USUARIOS = [f"user_{i:02d}" for i in range(1, 21)]  # user_01 al user_20

# ── Generadores de eventos ─────────────────────────────────────────
def timestamp():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def evento_page_view(prod, user):
    return {
        "type":       "page_view",
        "product_id": prod["product_id"],
        "product":    prod["product"],
        "category":   prod["category"],
        "user_id":    user,
        "timestamp":  timestamp(),
    }

def evento_add_to_cart(prod, user):
    return {
        "type":       "add_to_cart",
        "product_id": prod["product_id"],
        "product":    prod["product"],
        "price":      prod["price"],
        "quantity":   random.randint(1, 3),
        "user_id":    user,
        "timestamp":  timestamp(),
    }

def evento_purchase(prod, user):
    qty = random.randint(1, 3)
    return {
        "type":       "purchase",
        "product_id": prod["product_id"],
        "product":    prod["product"],
        "price":      prod["price"],
        "quantity":   qty,
        "total":      prod["price"] * qty,
        "user_id":    user,
        "timestamp":  timestamp(),
    }

def evento_cart_abandon(user):
    return {
        "type":        "cart_abandon",
        "user_id":     user,
        "items_count": random.randint(1, 4),
        "cart_value":  random.choice([p["price"] for p in PRODUCTOS]),
        "timestamp":   timestamp(),
    }

def evento_search(user):
    queries = ["laptop barata", "celular gama alta", "auriculares gaming",
               "monitor para diseño", "teclado mecánico", "tablet para estudiar"]
    return {
        "type":          "search",
        "query":         random.choice(queries),
        "results_count": random.randint(3, 20),
        "user_id":       user,
        "timestamp":     timestamp(),
    }

def generar_evento():
    prod = random.choice(PRODUCTOS)
    user = random.choice(USUARIOS)
    # Pesos: más page_views y purchases, menos abandono
    tipo = random.choices(
        ["purchase", "page_view", "add_to_cart", "cart_abandon", "search"],
        weights=[30, 35, 20, 10, 5]
    )[0]
    if tipo == "purchase":    return evento_purchase(prod, user)
    if tipo == "page_view":   return evento_page_view(prod, user)
    if tipo == "add_to_cart": return evento_add_to_cart(prod, user)
    if tipo == "cart_abandon":return evento_cart_abandon(user)
    return evento_search(user)

# ── Main ───────────────────────────────────────────────────────────
def main():
    producer = Producer({"bootstrap.servers": KAFKA_BROKER})

    print(f"Simulador iniciado → Kafka: {KAFKA_BROKER} | Topic: {TOPIC} | {EVENTOS_POR_SEGUNDO} eventos/seg")
    print("Ctrl+C para detener\n")

    total = 0
    intervalo = 1.0 / EVENTOS_POR_SEGUNDO

    try:
        while True:
            evento = generar_evento()
            msg    = json.dumps(evento)

            producer.produce(
                TOPIC,
                key=evento["user_id"],   # clave = user_id → mismo usuario, misma partición
                value=msg
            )
            producer.poll(0)

            total += 1
            print(f"[{total:>5}] {evento['type']:<15} {evento.get('product', ''):<20} {evento['user_id']}")

            time.sleep(intervalo)

    except KeyboardInterrupt:
        print(f"\nDetenido. Total enviados: {total}")
    finally:
        producer.flush()

if __name__ == "__main__":
    main()
