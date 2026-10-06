-- =============================================================================
-- 00_carga.sql — Creación del esquema y carga del dataset
-- Motor: PostgreSQL 14+
-- Ejecutar desde la raíz del repo:  psql -d iol -f sql/00_carga.sql
-- =============================================================================

DROP SCHEMA IF EXISTS iol CASCADE;
CREATE SCHEMA iol;
SET search_path TO iol;

-- 1) Tabla staging: todo como texto, tal cual viene en el CSV -----------------
CREATE TABLE operaciones_raw (
    fecha               TEXT,
    "tipoTran"          TEXT,
    id_cliente          TEXT,
    descripcion_titulo  TEXT,
    moneda              TEXT,
    simbolo_titulo      TEXT,
    cantidad            TEXT,
    precio              TEXT,
    id_transaccion      TEXT,
    origen              TEXT
);

\copy operaciones_raw FROM 'data/raw/Challenge_iol_data_set.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- 2) Tabla tipada + columnas derivadas ---------------------------------------
--    * fecha_utc   : timestamp original (el dataset declara UTC, ISO 8601)
--    * fecha_art   : misma marca en hora Argentina (UTC-3), que es el huso del mercado (BYMA)
--    * monto       : cantidad * precio, en la moneda original de la operación
--    * ms_flag     : milisegundos del timestamp (.000 / .010) — particularidad detectada
CREATE TABLE operaciones AS
SELECT
    id_transaccion,
    id_cliente,
    fecha::timestamptz                                          AS fecha_utc,
    (fecha::timestamptz AT TIME ZONE 'America/Argentina/Buenos_Aires') AS fecha_art,
    (fecha::timestamptz AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS dia_art,
    EXTRACT(HOUR FROM fecha::timestamptz AT TIME ZONE 'America/Argentina/Buenos_Aires')::int AS hora_art,
    EXTRACT(ISODOW FROM fecha::timestamptz AT TIME ZONE 'America/Argentina/Buenos_Aires')::int AS dow_art, -- 1=lun … 7=dom
    "tipoTran"                    AS tipo_tran,
    descripcion_titulo,
    simbolo_titulo,
    moneda,
    origen,
    cantidad::bigint              AS cantidad,
    precio::numeric(20,6)         AS precio,
    (cantidad::numeric * precio::numeric)::numeric(24,4) AS monto,
    substring(fecha FROM '\.(\d{3})Z$') AS ms_flag
FROM operaciones_raw;

ALTER TABLE operaciones ADD PRIMARY KEY (id_transaccion);
CREATE INDEX ix_op_cliente ON operaciones (id_cliente);
CREATE INDEX ix_op_dia     ON operaciones (dia_art);
CREATE INDEX ix_op_simbolo ON operaciones (simbolo_titulo);

-- 3) Control de carga ---------------------------------------------------------
SELECT 'raw' AS tabla, count(*) FROM operaciones_raw
UNION ALL
SELECT 'tipada', count(*) FROM operaciones;
