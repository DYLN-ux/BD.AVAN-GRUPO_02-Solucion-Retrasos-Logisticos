/* ==========================================================
   SECCION 5.4 - PRUEBAS DE CALIDAD, SEGURIDAD Y ACEPTACION
   Base: DW_Entregas (SQL Server / SSMS)
   Cada bloque lleva el ID de la tabla del informe (T-01 ... T-17).
   Ejecutar bloque por bloque y tomar captura (evidencia E-10).
   ========================================================== */
USE DW_Entregas;
GO

/* ---------- T-01  Conteo de staging (esperado 180,519) ---------- */
SELECT 'T-01' AS Prueba, COUNT(*) AS Filas_Staging,
       CASE WHEN COUNT(*) = 180519 THEN 'CUMPLE' ELSE 'REVISAR' END AS Estado
FROM Stg_Entregas_Raw;

/* ---------- T-02  Fechas (esperado 0 invalidas, 65,752 distintas) ----------
   Ajusta el nombre de la columna de fecha a como quedo en tu staging.     */
-- SELECT 'T-02' AS Prueba,
--        SUM(CASE WHEN TRY_CONVERT(datetime,[order date (DateOrders)],101) IS NULL THEN 1 ELSE 0 END) AS Fechas_Invalidas,
--        COUNT(DISTINCT [order date (DateOrders)]) AS Fechas_Distintas
-- FROM Stg_Entregas_Raw;
SELECT 'T-02' AS Prueba, COUNT(*) AS Filas_Dim_Tiempo,
       CASE WHEN COUNT(*) = 65752 THEN 'CUMPLE' ELSE 'REVISAR' END AS Estado
FROM Dimension_Tiempo;

/* ---------- T-03  Entrega_Tardia (origen 98,977; DW esperado 98,973) ---------- */
SELECT 'T-03' AS Prueba,
       SUM(Entrega_Tardia) AS Tardias,
       SUM(CASE WHEN Entrega_Tardia NOT IN (0,1) THEN 1 ELSE 0 END) AS Valores_Fuera_De_0_1
FROM Hechos_Entregas;

SELECT 'T-03b' AS Prueba, t.EstadoEntrega, h.Entrega_Tardia, COUNT(*) AS Filas
FROM Hechos_Entregas h
JOIN Dimension_Transporte t ON t.idTransporte = h.idTransporte_FK
GROUP BY t.EstadoEntrega, h.Entrega_Tardia
ORDER BY t.EstadoEntrega;   -- 'Late delivery' solo con 1; los demas solo con 0

/* ---------- T-04 / Q1  Indicadores globales (esperado 54.83 %, 3.50 y 2.93) ---------- */
SET STATISTICS TIME ON;
SELECT 'Q1' AS Consulta,
       COUNT(*)                                          AS Total_Entregas,
       SUM(Entrega_Tardia)                               AS Entregas_Tardias,
       CAST(100.0*SUM(Entrega_Tardia)/COUNT(*) AS DECIMAL(6,2)) AS Pct_Tardias,
       CAST(AVG(1.0*Dias_Envio_Real) AS DECIMAL(6,2))        AS Prom_Dias_Real,
       CAST(AVG(1.0*Dias_Envio_Programado) AS DECIMAL(6,2))  AS Prom_Dias_Programado,
       SUM(Ventas) AS Ventas_Totales, SUM(Ganancia) AS Ganancia_Total
FROM Hechos_Entregas;

/* ---------- Q2  % tardias por modo de envio (T-08) ---------- */
SELECT 'Q2' AS Consulta, t.ModoEnvio,
       COUNT(*) AS Entregas, SUM(h.Entrega_Tardia) AS Tardias,
       CAST(100.0*SUM(h.Entrega_Tardia)/COUNT(*) AS DECIMAL(6,2)) AS Pct_Tardias
FROM Hechos_Entregas h
JOIN Dimension_Transporte t ON t.idTransporte = h.idTransporte_FK
GROUP BY t.ModoEnvio ORDER BY Pct_Tardias DESC;

/* ---------- Q3  Tardias por region de destino y categoria ---------- */
SELECT 'Q3' AS Consulta, u.RegionDestino, p.NombreCategoria,
       SUM(h.Entrega_Tardia) AS Tardias
FROM Hechos_Entregas h
JOIN Dimension_Ubicacion u ON u.idUbicacion = h.idUbicacion_FK
JOIN Dimension_Producto  p ON p.idProducto  = h.idProducto_FK
GROUP BY u.RegionDestino, p.NombreCategoria
ORDER BY Tardias DESC;

/* ---------- Q4  Serie por anio y mes ---------- */
SELECT 'Q4' AS Consulta, d.[Año], d.Mes,
       SUM(h.Entrega_Tardia) AS Tardias, SUM(h.Ganancia) AS Ganancia_Total
FROM Hechos_Entregas h
JOIN Dimension_Tiempo d ON d.idTiempo = h.idTiempo_FK
GROUP BY d.[Año], d.Mes
ORDER BY d.[Año], d.Mes;
SET STATISTICS TIME OFF;

/* ---------- T-05  Completitud del ETL (esperado 100 %; hoy 180,511 / 180,519) ---------- */
SELECT 'T-05' AS Prueba,
       (SELECT COUNT(*) FROM Stg_Entregas_Raw) AS Filas_Staging,
       (SELECT COUNT(*) FROM Hechos_Entregas)  AS Filas_Hechos,
       CAST(100.0*(SELECT COUNT(*) FROM Hechos_Entregas)
                 /(SELECT COUNT(*) FROM Stg_Entregas_Raw) AS DECIMAL(8,4)) AS Completitud_Pct;

-- Filas perdidas: ajusta el nombre de las columnas de staging (Order Id, Order Item Id, Customer Lname)
-- SELECT s.[Order Id], s.[Order Item Id], s.[Customer Lname]
-- FROM Stg_Entregas_Raw s
-- LEFT JOIN Hechos_Entregas h
--        ON h.idOrder = TRY_CAST(s.[Order Id] AS INT)
--       AND h.idOrder_Item = TRY_CAST(s.[Order Item Id] AS INT)
-- WHERE h.idOrder IS NULL;      -- se esperan 8 filas, todas con Customer Lname vacio

/* ---------- T-06  Huerfanos por FK (esperado 0 en las 5) ---------- */
SELECT 'T-06' AS Prueba,
  (SELECT COUNT(*) FROM Hechos_Entregas h LEFT JOIN Dimension_Cliente    d ON d.idCliente    = h.idCliente_FK    WHERE d.idCliente    IS NULL) AS Huerfanos_Cliente,
  (SELECT COUNT(*) FROM Hechos_Entregas h LEFT JOIN Dimension_Producto   d ON d.idProducto   = h.idProducto_FK   WHERE d.idProducto   IS NULL) AS Huerfanos_Producto,
  (SELECT COUNT(*) FROM Hechos_Entregas h LEFT JOIN Dimension_Ubicacion  d ON d.idUbicacion  = h.idUbicacion_FK  WHERE d.idUbicacion  IS NULL) AS Huerfanos_Ubicacion,
  (SELECT COUNT(*) FROM Hechos_Entregas h LEFT JOIN Dimension_Tiempo     d ON d.idTiempo     = h.idTiempo_FK     WHERE d.idTiempo     IS NULL) AS Huerfanos_Tiempo,
  (SELECT COUNT(*) FROM Hechos_Entregas h LEFT JOIN Dimension_Transporte d ON d.idTransporte = h.idTransporte_FK WHERE d.idTransporte IS NULL) AS Huerfanos_Transporte;

/* ---------- T-09  Unicidad de (idOrder, idOrder_Item) (esperado 0) ---------- */
SELECT 'T-09' AS Prueba, COUNT(*) AS Claves_Duplicadas
FROM (SELECT idOrder, idOrder_Item FROM Hechos_Entregas
      GROUP BY idOrder, idOrder_Item HAVING COUNT(*) > 1) x;

/* ---------- T-10  Nulos en medidas y claves (esperado 0) ---------- */
SELECT 'T-10' AS Prueba,
  SUM(CASE WHEN Cantidad_Pedido       IS NULL THEN 1 ELSE 0 END) AS Nulos_Cantidad,
  SUM(CASE WHEN Ventas                IS NULL THEN 1 ELSE 0 END) AS Nulos_Ventas,
  SUM(CASE WHEN Ganancia              IS NULL THEN 1 ELSE 0 END) AS Nulos_Ganancia,
  SUM(CASE WHEN Dias_Envio_Real       IS NULL THEN 1 ELSE 0 END) AS Nulos_DiasReal,
  SUM(CASE WHEN Dias_Envio_Programado IS NULL THEN 1 ELSE 0 END) AS Nulos_DiasProg,
  SUM(CASE WHEN Entrega_Tardia        IS NULL THEN 1 ELSE 0 END) AS Nulos_Tardia
FROM Hechos_Entregas;

/* ---------- T-11  Rangos validos (esperado: 0-6, 0-4, 1-5, ventas > 0) ---------- */
SELECT 'T-11' AS Prueba,
  MIN(Dias_Envio_Real) AS Min_Real, MAX(Dias_Envio_Real) AS Max_Real,
  MIN(Dias_Envio_Programado) AS Min_Prog, MAX(Dias_Envio_Programado) AS Max_Prog,
  MIN(Cantidad_Pedido) AS Min_Cant, MAX(Cantidad_Pedido) AS Max_Cant,
  SUM(CASE WHEN Ventas <= 0 THEN 1 ELSE 0 END) AS Ventas_No_Positivas,
  SUM(CASE WHEN Ganancia < 0 THEN 1 ELSE 0 END) AS Filas_Ganancia_Negativa
FROM Hechos_Entregas;

/* ---------- T-12  Columnas personales en el DW (esperado 0 de correo/clave/calle/zip) ---------- */
SELECT 'T-12' AS Prueba, TABLE_NAME, COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME LIKE '%mail%' OR COLUMN_NAME LIKE '%pass%' OR COLUMN_NAME LIKE '%clave%'
   OR COLUMN_NAME LIKE '%street%' OR COLUMN_NAME LIKE '%calle%' OR COLUMN_NAME LIKE '%zip%'
   OR COLUMN_NAME LIKE '%postal%';
-- Informativo: Nombre y Apellido SI existen en Dimension_Cliente (ocultarlos en Power BI)
SELECT 'T-12b' AS Prueba, TABLE_NAME, COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Dimension_Cliente' AND COLUMN_NAME IN ('Nombre','Apellido');

/* ---------- T-14  Usuario de solo lectura (esperado: INSERT y DELETE rechazados) ---------- */
IF USER_ID('usr_lectura_test') IS NOT NULL DROP USER usr_lectura_test;
CREATE USER usr_lectura_test WITHOUT LOGIN;
ALTER ROLE db_datareader ADD MEMBER usr_lectura_test;

EXECUTE AS USER = 'usr_lectura_test';
    SELECT 'T-14 SELECT permitido' AS Prueba, COUNT(*) AS Filas FROM Hechos_Entregas;
    BEGIN TRY
        DELETE FROM Hechos_Entregas WHERE idOrder = -1;
        SELECT 'T-14 DELETE' AS Prueba, 'PERMITIDO (FALLA LA PRUEBA)' AS Estado;
    END TRY
    BEGIN CATCH
        SELECT 'T-14 DELETE' AS Prueba, ERROR_NUMBER() AS Error_Num, ERROR_MESSAGE() AS Mensaje;  -- esperado 229
    END CATCH
    BEGIN TRY
        INSERT INTO Dimension_Transporte (ModoEnvio) VALUES ('PRUEBA');
        SELECT 'T-14 INSERT' AS Prueba, 'PERMITIDO (FALLA LA PRUEBA)' AS Estado;
    END TRY
    BEGIN CATCH
        SELECT 'T-14 INSERT' AS Prueba, ERROR_NUMBER() AS Error_Num, ERROR_MESSAGE() AS Mensaje;  -- esperado 229
    END CATCH
REVERT;
DROP USER usr_lectura_test;

/* ---------- T-15  Conteos para aceptacion (esperado 18,683 / 118 / 3,772 / 65,752 / 64 / 180,511) ---------- */
SELECT 'T-15' AS Prueba,
  (SELECT COUNT(*) FROM Dimension_Cliente)    AS Cliente,
  (SELECT COUNT(*) FROM Dimension_Producto)   AS Producto,
  (SELECT COUNT(*) FROM Dimension_Ubicacion)  AS Ubicacion,
  (SELECT COUNT(*) FROM Dimension_Tiempo)     AS Tiempo,
  (SELECT COUNT(*) FROM Dimension_Transporte) AS Transporte,
  (SELECT COUNT(*) FROM Hechos_Entregas)      AS Hechos;
GO
