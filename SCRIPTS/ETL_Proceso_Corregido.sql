USE DW_Entregas;
GO
SET NOCOUNT ON;
GO

/* ============================================================================
   ACTIVIDAD 07 - PROCESO ETL (PUNTO 4) - VERSION CORREGIDA
   Cambios: (1) apellido vacio -> 'Sin apellido' (recupera 8 filas);
            (2) JOIN de cliente con las 5 columnas de la dimension (evita
                filas ambiguas y asignacion arbitraria de segmento/pais).
   ============================================================================ */

-- 1. LIMPIEZA PREVIA DE TABLAS
DELETE FROM Hechos_Entregas;
DELETE FROM Dimension_Cliente;
DELETE FROM Dimension_Producto;
DELETE FROM Dimension_Ubicacion;
DELETE FROM Dimension_Tiempo;
DELETE FROM Dimension_Transporte;

DBCC CHECKIDENT ('Dimension_Cliente',    RESEED, 0);
DBCC CHECKIDENT ('Dimension_Producto',   RESEED, 0);
DBCC CHECKIDENT ('Dimension_Ubicacion',  RESEED, 0);
DBCC CHECKIDENT ('Dimension_Tiempo',     RESEED, 0);
DBCC CHECKIDENT ('Dimension_Transporte', RESEED, 0);
GO

-- 2. ETAPA DE EXTRACCIÓN (STAGING)
IF OBJECT_ID('Stg_Entregas_Raw') IS NOT NULL DROP TABLE Stg_Entregas_Raw;
GO

CREATE TABLE Stg_Entregas_Raw (
    Type VARCHAR(50), DiasEnvioReal VARCHAR(50), DiasEnvioProgramado VARCHAR(50), 
    BeneficioPorOrden VARCHAR(50), VentasPorCliente VARCHAR(50), DeliveryStatus VARCHAR(50), 
    LateDeliveryRisk VARCHAR(50), CategoryI VARCHAR(50), CategoryName VARCHAR(100), 
    CustomerCity VARCHAR(100), CustomerCountry VARCHAR(100), CustomerEmail VARCHAR(100), 
    CustomerFname VARCHAR(100), CustomerId VARCHAR(50), CustomerLname VARCHAR(100), 
    CustomerPassword VARCHAR(100), CustomerSegment VARCHAR(100), CustomerState VARCHAR(100), 
    CustomerStreet VARCHAR(200), CustomerZipcode VARCHAR(50), DepartmentId VARCHAR(50), 
    DepartmentName VARCHAR(100), Latitude VARCHAR(50), Longitude VARCHAR(50), Market VARCHAR(50), 
    OrderCity VARCHAR(100), OrderCountry VARCHAR(100), OrderCustomerId VARCHAR(50), 
    OrderDate VARCHAR(50), OrderId VARCHAR(50), OrderItemCardprodId VARCHAR(50), 
    OrderItemDiscount VARCHAR(50), OrderItemDiscountRate VARCHAR(50), OrderItemId VARCHAR(50), 
    OrderItemProductPrice VARCHAR(50), OrderItemProfitRatio VARCHAR(50), OrderItemQuantity VARCHAR(50), 
    Sales VARCHAR(50), OrderItemTotal VARCHAR(50), OrderProfitPerOrder VARCHAR(50), 
    OrderRegion VARCHAR(100), OrderState VARCHAR(100), OrderStatus VARCHAR(50), 
    OrderZipcode VARCHAR(50), ProductCardId VARCHAR(50), ProductCategoryId VARCHAR(50), 
    ProductDescription VARCHAR(500), ProductImage VARCHAR(500), ProductName VARCHAR(200), 
    ProductPrice VARCHAR(50), ProductStatus VARCHAR(50), ShippingDate VARCHAR(50), 
    ShippingMode VARCHAR(50) 
);
GO

DECLARE @ruta NVARCHAR(500) = N'C:\ETL\DataCoSupplyChainDataset.csv';
DECLARE @sql  NVARCHAR(MAX) = N'
BULK INSERT Stg_Entregas_Raw
FROM ''' + @ruta + N'''
WITH (
    FORMAT          = ''CSV'',   
    FIELDQUOTE      = ''"'',
    FIRSTROW        = 2,            
    FIELDTERMINATOR = '','',
    ROWTERMINATOR   = ''0x0a'',
    CODEPAGE        = ''1252'',    
    TABLOCK
);';
EXEC sp_executesql @sql;
GO

-- 3. CARGA DE DIMENSIONES
INSERT INTO Dimension_Cliente (Nombre, Apellido, Segmento, Ciudad, Pais)
SELECT DISTINCT 
    LEFT(TRIM(CustomerFname), 50), LEFT(ISNULL(NULLIF(TRIM(CustomerLname), ''), 'Sin apellido'), 50), 
    LEFT(TRIM(CustomerSegment), 50), LEFT(TRIM(CustomerCity), 70), LEFT(TRIM(CustomerCountry), 50)
FROM Stg_Entregas_Raw WHERE CustomerFname IS NOT NULL AND TRIM(CustomerFname) <> '';

INSERT INTO Dimension_Producto (NombreProducto, idCategoria, NombreCategoria, idDepartamento, NombreDepartamento, PrecioProducto)
SELECT 
    TRIM(ProductName), MAX(TRY_CAST(ProductCategoryId AS INT)), LEFT(MAX(TRIM(CategoryName)), 60),
    MAX(TRY_CAST(DepartmentId AS INT)), LEFT(MAX(TRIM(DepartmentName)), 60), MAX(TRY_CAST(ProductPrice AS DECIMAL(12,2)))
FROM Stg_Entregas_Raw WHERE ProductName IS NOT NULL AND TRIM(ProductName) <> '' GROUP BY TRIM(ProductName);

INSERT INTO Dimension_Ubicacion (CiudadDestino, EstadoDestino, PaisDestino, RegionDestino)
SELECT DISTINCT 
    LEFT(TRIM(OrderCity), 70), LEFT(TRIM(OrderState), 50), LEFT(TRIM(OrderCountry), 50), LEFT(TRIM(OrderRegion), 50)
FROM Stg_Entregas_Raw WHERE OrderCity IS NOT NULL AND TRIM(OrderCity) <> '';

WITH Fechas AS (
    SELECT DISTINCT TRY_CONVERT(DATETIME, OrderDate, 101) AS F FROM Stg_Entregas_Raw WHERE OrderDate IS NOT NULL
)
INSERT INTO Dimension_Tiempo (Fecha, [Año], Trimestre, Mes, Semana, DiaSemana)
SELECT F, YEAR(F), DATEPART(QUARTER, F), MONTH(F), DATEPART(WEEK, F), DATENAME(WEEKDAY, F)
FROM Fechas WHERE F IS NOT NULL;

INSERT INTO Dimension_Transporte (ModoEnvio, EstadoEntrega, EstadoOrden, TipoPago)
SELECT DISTINCT 
    LEFT(TRIM(ShippingMode), 50), LEFT(TRIM(DeliveryStatus), 50), LEFT(TRIM(OrderStatus), 50), LEFT(TRIM(Type), 50)
FROM Stg_Entregas_Raw WHERE ShippingMode IS NOT NULL;
GO

-- 4. CARGA DE HECHOS GARANTIZANDO UNICIDAD DE CLAVE PRIMARIA (ROW_NUMBER)
WITH Hechos_Preparados AS (
    SELECT 
        p.idProducto AS idProducto_FK,
        u.idUbicacion AS idUbicacion_FK,
        c.idCliente AS idCliente_FK,
        t.idTiempo AS idTiempo_FK,
        tr.idTransporte AS idTransporte_FK,
        TRY_CAST(raw.OrderId AS INT) AS idOrder,
        TRY_CAST(raw.OrderItemId AS INT) AS idOrder_Item,
        TRY_CAST(raw.OrderItemQuantity AS INT) AS Cantidad_Pedido,
        TRY_CAST(raw.Sales AS DECIMAL(12,2)) AS Ventas,
        TRY_CAST(raw.OrderProfitPerOrder AS DECIMAL(12,2)) AS Ganancia,
        TRY_CAST(raw.DiasEnvioReal AS INT) AS Dias_Envio_Real,
        TRY_CAST(raw.DiasEnvioProgramado AS INT) AS Dias_Envio_Programado,
        TRY_CAST(raw.LateDeliveryRisk AS INT) AS Entrega_Tardia,
        ROW_NUMBER() OVER(
            PARTITION BY TRY_CAST(raw.OrderId AS INT), TRY_CAST(raw.OrderItemId AS INT) 
            ORDER BY TRY_CAST(raw.OrderId AS INT)
        ) AS Fila_Num
    FROM Stg_Entregas_Raw raw
    INNER JOIN Dimension_Producto p ON p.NombreProducto = TRIM(raw.ProductName)
    INNER JOIN Dimension_Cliente c ON c.Nombre = LEFT(TRIM(raw.CustomerFname), 50)
                                     AND c.Apellido = LEFT(ISNULL(NULLIF(TRIM(raw.CustomerLname), ''), 'Sin apellido'), 50)
                                     AND c.Segmento = LEFT(TRIM(raw.CustomerSegment), 50)
                                     AND c.Ciudad   = LEFT(TRIM(raw.CustomerCity), 70)
                                     AND c.Pais     = LEFT(TRIM(raw.CustomerCountry), 50)
    INNER JOIN Dimension_Ubicacion u ON u.CiudadDestino = LEFT(TRIM(raw.OrderCity), 70) AND u.EstadoDestino = LEFT(TRIM(raw.OrderState), 50) AND u.PaisDestino = LEFT(TRIM(raw.OrderCountry), 50)
    INNER JOIN Dimension_Tiempo t ON t.Fecha = TRY_CONVERT(DATETIME, raw.OrderDate, 101)
    INNER JOIN Dimension_Transporte tr ON tr.ModoEnvio = LEFT(TRIM(raw.ShippingMode), 50) AND tr.EstadoEntrega = LEFT(TRIM(raw.DeliveryStatus), 50) AND tr.EstadoOrden = LEFT(TRIM(raw.OrderStatus), 50) AND tr.TipoPago = LEFT(TRIM(raw.Type), 50)
    WHERE TRY_CAST(raw.OrderId AS INT) IS NOT NULL 
      AND TRY_CAST(raw.OrderItemId AS INT) IS NOT NULL
)
INSERT INTO Hechos_Entregas (
    idProducto_FK, idUbicacion_FK, idCliente_FK, idTiempo_FK, idTransporte_FK,
    idOrder, idOrder_Item, Cantidad_Pedido, Ventas, Ganancia, Dias_Envio_Real, Dias_Envio_Programado, Entrega_Tardia
)
SELECT 
    idProducto_FK, idUbicacion_FK, idCliente_FK, idTiempo_FK, idTransporte_FK,
    idOrder, idOrder_Item, Cantidad_Pedido, Ventas, Ganancia, Dias_Envio_Real, Dias_Envio_Programado, Entrega_Tardia
FROM Hechos_Preparados
WHERE Fila_Num = 1; -- Elimina cualquier duplicado exacto de la clave primaria
GO

-- 5. MUESTRA DE RESULTADOS CARGADOS
SELECT 'Dimension_Cliente' AS Tabla, COUNT(*) AS TotalRegistros FROM Dimension_Cliente
UNION ALL
SELECT 'Dimension_Producto', COUNT(*) FROM Dimension_Producto
UNION ALL
SELECT 'Dimension_Ubicacion', COUNT(*) FROM Dimension_Ubicacion
UNION ALL
SELECT 'Dimension_Tiempo', COUNT(*) FROM Dimension_Tiempo
UNION ALL
SELECT 'Dimension_Transporte', COUNT(*) FROM Dimension_Transporte
UNION ALL
SELECT 'Hechos_Entregas', COUNT(*) FROM Hechos_Entregas;
GO

-- 6. CONTROLES DE CALIDAD DEL ETL (evidencia para las pruebas T-05 y T-06)
SELECT 'Staging' AS Origen, COUNT(*) AS Filas FROM Stg_Entregas_Raw
UNION ALL
SELECT 'Hechos_Entregas', COUNT(*) FROM Hechos_Entregas;   -- esperado: 180519 y 180519
GO

-- RNF-07: el staging contiene correo, contrasena (enmascarados) y calle.
-- Cuando terminen las pruebas puede eliminarse:
-- DROP TABLE Stg_Entregas_Raw;

SELECT TOP 10 * FROM DW_Entregas.dbo.Hechos_Entregas;
