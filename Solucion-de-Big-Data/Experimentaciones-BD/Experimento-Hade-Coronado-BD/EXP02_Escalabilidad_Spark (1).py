# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "6"
# ///
# MAGIC %md
# MAGIC ## EXPERIMENTACIÓN — EXP-02: Escalabilidad con volumen creciente
# MAGIC **Objetivo:** evaluar cómo responde la solución Big Data al aumentar el volumen de datos de 180 519 a 1 805 190 filas (1x, 2x, 5x, 10x), verificando los criterios CA04, CA05 y CA09.
# MAGIC
# MAGIC Requisito: haber ejecutado antes el notebook de la solución, que crea la tabla `tb_supply_chain`.

# COMMAND ----------

from pyspark.sql import functions as F

dbutils.widgets.text("codEstudiante", "")
codEstudiante = dbutils.widgets.get("codEstudiante")

NOMBRE_TABLA = f"tb_supply_chain_{codEstudiante}" if codEstudiante else "tb_supply_chain"
df = spark.table(NOMBRE_TABLA)
print("Tabla base:", NOMBRE_TABLA, "| filas:", df.count())

# COMMAND ----------

import time, statistics, platform
import pandas as pd
from pyspark.sql import functions as F

ESCALAS   = [1, 2, 5, 10]
N_REP     = 5
OFFSET_ID = 1_000_000
SUF = f"_{codEstudiante}" if codEstudiante else ""

entorno = {"spark_version": spark.version, "python": platform.python_version(),
           "fecha": time.strftime("%Y-%m-%d %H:%M:%S")}
print(entorno)

def consultas(t):
    q1 = t.agg(F.count("*").alias("total"),
               F.sum("late_delivery_risk").alias("tardias"),
               F.round(F.avg("late_delivery_risk") * 100, 2).alias("pct_tardias"),
               F.round(F.avg("days_for_shipping_real"), 2).alias("dias_reales"),
               F.round(F.avg("days_for_shipment_scheduled"), 2).alias("dias_programados"),
               F.round(F.sum("sales"), 2).alias("ventas"))
    q2 = (t.groupBy("shipping_mode")
            .agg(F.count("*").alias("items"),
                 F.sum("late_delivery_risk").alias("tardias"),
                 F.round(F.avg("late_delivery_risk") * 100, 2).alias("pct_tardias"))
            .orderBy(F.desc("pct_tardias")))
    q3 = (t.groupBy("order_region", "category_name")
            .agg(F.sum("late_delivery_risk").alias("tardias"))
            .orderBy(F.desc("tardias")))
    q4 = (t.groupBy("order_year", "order_month")
            .agg(F.sum("late_delivery_risk").alias("tardias"),
                 F.round(F.sum("order_profit_per_order"), 2).alias("ganancia"))
            .orderBy("order_year", "order_month"))
    return {"Q1": q1, "Q2": q2, "Q3": q3, "Q4": q4}

def medir(dfq):
    t0 = time.perf_counter()
    filas = dfq.collect()
    return time.perf_counter() - t0, len(filas)

def correr_consultas(tabla, escenario, escala, particiones=0):
    t = spark.table(tabla)
    n_filas = t.count()
    registros = []
    for q, dfq in consultas(t).items():
        medir(dfq)                                   
        for r in range(1, N_REP + 1):
            seg, n_res = medir(dfq)
            registros.append({"escenario": escenario, "escala": escala, "particiones": particiones,
                              "filas": n_filas, "consulta": q, "repeticion": r,
                              "segundos": round(seg, 4), "filas_resultado": n_res,
                              "filas_por_seg": round(n_filas / seg)})
    return registros

def resumen(reg_pd, claves):
    g = reg_pd.groupby(claves + ["consulta"])["segundos"]
    out = g.agg(mediana="median", media="mean", desv="std", minimo="min", maximo="max").reset_index()
    out["cv_pct"] = (out["desv"] / out["media"] * 100).round(2)
    return out.round(4)

# COMMAND ----------

# Ingesta: creamos una tabla por escala (1x, 2x, 5x, 10x)
ingesta = []
for k in ESCALAS:
    tabla = f"exp02_escala_{k}x{SUF}"
    t0 = time.perf_counter()
    d_k = (df.withColumn("rep", F.explode(F.sequence(F.lit(1), F.lit(k))))
             .withColumn("order_id", F.col("order_id") + (F.col("rep") - 1) * OFFSET_ID)
             .drop("rep"))
    d_k.write.mode("overwrite").saveAsTable(tabla)
    seg = time.perf_counter() - t0
    n = spark.table(tabla).count()
    ingesta.append({"escala": k, "tabla": tabla, "filas": n, "ingesta_seg": round(seg, 2),
                    "ingesta_filas_por_seg": round(n / seg)})
    print(f"{k:>2}x -> {n:>9,} filas | ingesta {seg:6.2f} s")

ingesta_pd = pd.DataFrame(ingesta)
display(ingesta_pd)

# COMMAND ----------

# Validación de integridad: no debe haber claves duplicadas
for k in ESCALAS:
    t = spark.table(f"exp02_escala_{k}x{SUF}")
    dup = t.groupBy("order_id", "order_item_id").count().filter("count > 1").count()
    print(f"{k:>2}x | filas={t.count():>9,} | claves duplicadas={dup}")

# COMMAND ----------

# Medición de las consultas Q1-Q4 en cada escala
reg = []
for k in ESCALAS:
    print(f"Midiendo escala {k}x ...")
    reg += correr_consultas(f"exp02_escala_{k}x{SUF}", "EXP-02", k)

reg_02 = pd.DataFrame(reg)
res_02 = resumen(reg_02, ["escala"])
display(res_02)

# COMMAND ----------

# Evaluación de criterios CA09 (escalabilidad), CA04 (estabilidad) y CA05 (tiempo máximo)
med_escala = res_02.groupby("escala")["mediana"].median().rename("mediana_Q1_Q4_s").reset_index()
base = med_escala.loc[med_escala["escala"] == 1, "mediana_Q1_Q4_s"].iloc[0]
med_escala["razon_tiempo"] = (med_escala["mediana_Q1_Q4_s"] / base).round(2)
med_escala["CA09_cumple"]  = med_escala["razon_tiempo"] <= med_escala["escala"]

res_02["CA04_cumple"] = res_02.apply(lambda r: r["cv_pct"] <= (15 if r["mediana"] < 1 else 10), axis=1)
res_02["CA05_cumple"] = res_02["mediana"] <= 5

display(med_escala)
display(res_02[["escala", "consulta", "mediana", "cv_pct", "CA04_cumple", "CA05_cumple"]])

# COMMAND ----------

# Tabla para graficar:tiempo medido vs. crecimiento lineal de referencia
grafico = med_escala[["escala", "mediana_Q1_Q4_s"]].copy()
grafico["referencia_lineal"] = (base * grafico["escala"]).round(3)
display(grafico)

# Tabla por consulta (una línea por Q1..Q4)
display(res_02[["escala", "consulta", "mediana", "media", "cv_pct"]].sort_values(["consulta", "escala"]))

# COMMAND ----------

# Guardado de resultados (tablas Delta + CSV en el Volume)
def guardar(pdf, nombre):
    spark.createDataFrame(pdf).write.mode("overwrite").saveAsTable(nombre + SUF)
    ruta = f"/Volumes/workspace/default/datos/{nombre}{SUF}.csv"
    pdf.to_csv(ruta, index=False)
    print("Guardado:", nombre + SUF, "y", ruta)

guardar(reg_02,     "exp02_mediciones")
guardar(res_02,     "exp02_resumen")
guardar(med_escala, "exp02_escalabilidad")
guardar(ingesta_pd, "exp02_ingesta")