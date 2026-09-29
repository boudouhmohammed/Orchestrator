import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from sqlalchemy import create_engine

from app.consume_queue import consume_and_store_order
from app.orders import Base

BILLING_DB_USER = os.getenv("BILLING_DB_USER")
BILLING_DB_PASSWORD = os.getenv("BILLING_DB_PASSWORD")
BILLING_DB_NAME = os.getenv("BILLING_DB_NAME")

DB_URI = (
    "postgresql://"
    f"{BILLING_DB_USER}:{BILLING_DB_PASSWORD}"
    f"@billing-db:5432/{BILLING_DB_NAME}"
)

engine = create_engine(DB_URI)
Base.metadata.create_all(engine)

threading.Thread(
    target=consume_and_store_order,
    args=(engine,),
    daemon=True,
).start()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}')

    def log_message(self, format, *args):
        pass


server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
print("Listening on port 8080")
server.serve_forever()
