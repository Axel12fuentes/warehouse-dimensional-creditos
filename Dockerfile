# Postgres 16 + pg_cron.
# La imagen oficial no trae pg_cron, y lo necesitamos para programar las
# cargas del warehouse sin depender de un orquestador externo.
FROM postgres:16

RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-16-cron \
 && rm -rf /var/lib/apt/lists/*
