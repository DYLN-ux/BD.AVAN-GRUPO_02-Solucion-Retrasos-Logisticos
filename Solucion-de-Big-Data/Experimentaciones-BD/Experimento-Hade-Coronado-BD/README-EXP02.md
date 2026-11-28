# Experimentaciones de la solución Big Data

Diseño experimental y configuraciones de los experimentos realizados sobre la solución Big Data
(Apache Spark en Databricks Free Edition, cómputo serverless).

## 1. Índice de experimentos

| Código | Experimento | Integrante | Carpeta | Estado |
|---|---|---|---|---|
| EXP-02 | Escalabilidad con volumen creciente (1×, 2×, 5×, 10×) | Hade Coronado | `Experimento-Hade-Coronado-BD/` | Ejecutado (23/11 y 25/11/2026) |

## 2. Entorno y reproducibilidad (común a todos)

| Elemento | Valor |
|---|---|
| Plataforma | Databricks Free Edition, cómputo serverless |
| Apache Spark | 4.2.0 |
| Python | 3.12.3 |
| Dataset base | DataCoSupplyChainDataset.csv (180 519 filas, 53 columnas, ISO-8859-1) |
| Tabla procesada | tb_supply_chain (Delta, workspace.default), 180 519 filas × 51 columnas |
| Almacenamiento de resultados | Volume /Volumes/workspace/default/datos y tablas Delta |
| Requisito previo | Ejecutar el notebook de la solución (partes 1 a 6) para crear tb_supply_chain |

Regla de medición común: 1 corrida de calentamiento descartada + 5 repeticiones medidas
(EXP-02); mediana y coeficiente de variación (CV = desviación estándar muestral / media).

## 3. EXP-02 · Escalabilidad con volumen creciente

| Elemento | Diseño |
|---|---|
| Objetivo | Evaluar cómo responde la solución al aumentar el volumen de 180 519 a 1 805 190 filas, midiendo el tiempo de ingesta y de las consultas Q1–Q4. |
| Hipótesis | H6: el tiempo de las consultas crece como máximo de forma lineal con el volumen (T(k×)/T(1×) ≤ k) y mantiene CV ≤ 15 %. |
| Escenario | Spark en Databricks serverless sobre tablas Delta. |
| Dataset | Sintético, réplica determinista de tb_supply_chain: cada fila se repite k veces con explode(sequence(1, k)) y order_id se desplaza en 1 000 000 por réplica para mantener única la clave (order_id, order_item_id). |
| Variable independiente | Escala k ∈ {1, 2, 5, 10} (180 519; 361 038; 902 595; 1 805 190 filas). |
| Variables dependientes | Tiempo de ingesta (s), filas/s, tiempo de Q1–Q4 (s). |
| Métricas | Mediana, media, desviación estándar, CV, razón T(k×)/T(1×). |
| Consultas | Q1 indicadores globales; Q2 % tardías por modo de envío; Q3 tardías por región y categoría; Q4 tardías y ganancia por año y mes. |
| Controles | Mismo notebook y workspace, misma definición de Q1–Q4, calentamiento descartado, 5 repeticiones. |
| Criterios de aceptación | CA-04: CV ≤ 10 % (≤ 15 % si la mediana < 1 s). CA-05: mediana ≤ 5 s. CA-09: T(k×)/T(1×) ≤ k. |
| Validación del dataset | Filas = k × 180 519 y 0 claves duplicadas en las 4 escalas. |
| Procedimiento | 1) Leer tb_supply_chain. 2) Crear y guardar exp02_escala_{k}x. 3) Verificar unicidad de claves. 4) Medir Q1–Q4 (calentamiento + 5 repeticiones). 5) Calcular métricas y criterios. 6) Guardar exp02_* y los CSV. |
| Resultado esperado | H6 se cumple si la razón de tiempo no supera k. Se reportan los resultados sin asumir que la hipótesis se cumple. |
| Limitaciones | Datos replicados (misma distribución), una sola configuración serverless, cómputo compartido, rango de volumen acotado a 1.8 millones de filas. |
| Evidencias | Notebook EXP02_Escalabilidad_Spark (.ipynb y .html), CSV exp02_* en resultados/, capturas en `capturas/. |

## 4. Cómo reproducir
1. Importar los notebooks en Databricks (Workspace → ⋮ → Import) y usar cómputo Serverless.
2. Ejecutar el notebook de la solución (partes 1 a 6) para crear tb_supply_chain.
3. Ejecutar las celdas del experimento en orden.
4. Descargar los CSV desde Catalog → workspace → default → datos.