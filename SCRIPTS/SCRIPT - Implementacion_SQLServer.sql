/* ==========================================================
   ACTIVIDAD 07 - PUNTO 3: IMPLEMENTACION EN SQL SERVER
   Tema: Analisis de retrasos en entregas (BI y Big Data)
   Modelo: Estrella (1 tabla de hechos + 5 dimensiones)
   ========================================================== */

/* ----------------------------------------------------------
   1. CREAR BASE DE DATOS
   ---------------------------------------------------------- */
USE master;
GO

IF DB_ID('DW_Entregas') IS NOT NULL
BEGIN
    ALTER DATABASE DW_Entregas SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DW_Entregas;
END
GO

CREATE DATABASE DW_Entregas;
GO

USE DW_Entregas;
GO


-- 2. CREAR TABLAS DE DIMENSIONES (con su clave primaria)


-- Dimension Cliente
CREATE TABLE Dimension_Cliente (
    idCliente   INT IDENTITY(1,1) NOT NULL,
    Nombre      VARCHAR(50),
    Apellido    VARCHAR(50),
    Segmento    VARCHAR(50),
    Ciudad      VARCHAR(70),
    Pais        VARCHAR(50),
    CONSTRAINT PK_Dimension_Cliente PRIMARY KEY (idCliente)
);
GO

-- Dimension Producto
CREATE TABLE Dimension_Producto (
    idProducto          INT IDENTITY(1,1) NOT NULL,
    NombreProducto      VARCHAR(100),
    idCategoria         INT,
    NombreCategoria     VARCHAR(60),
    idDepartamento      INT,
    NombreDepartamento  VARCHAR(60),
    PrecioProducto      DECIMAL(12,2),
    CONSTRAINT PK_Dimension_Producto PRIMARY KEY (idProducto),
    CONSTRAINT UQ_Dimension_Producto_Nombre UNIQUE (NombreProducto)  -- 1 nombre = 1 producto (118 en el dataset)
);
GO

-- Dimension Ubicacion
CREATE TABLE Dimension_Ubicacion (
    idUbicacion    INT IDENTITY(1,1) NOT NULL,
    CiudadDestino  VARCHAR(70),
    EstadoDestino  VARCHAR(50),
    PaisDestino    VARCHAR(50),
    RegionDestino  VARCHAR(50),
    CONSTRAINT PK_Dimension_Ubicacion PRIMARY KEY (idUbicacion)
);
GO

-- Dimension Tiempo
CREATE TABLE Dimension_Tiempo (
    idTiempo   INT IDENTITY(1,1) NOT NULL,
    Fecha      DATETIME,
    [Año]      INT,
    Trimestre  INT,
    Mes        INT,
    Semana     INT,
    DiaSemana  VARCHAR(10),
    CONSTRAINT PK_Dimension_Tiempo PRIMARY KEY (idTiempo)
);
GO

-- Dimension Transporte
CREATE TABLE Dimension_Transporte (
    idTransporte  INT IDENTITY(1,1) NOT NULL,
    ModoEnvio     VARCHAR(50),
    EstadoEntrega VARCHAR(50),
    EstadoOrden   VARCHAR(50),
    TipoPago      VARCHAR(50),
    CONSTRAINT PK_Dimension_Transporte PRIMARY KEY (idTransporte)
);
GO

-- 3. CREAR TABLA DE HECHOS

CREATE TABLE Hechos_Entregas (
    -- Claves foraneas hacia las dimensiones
    idProducto_FK           INT NOT NULL,
    idUbicacion_FK          INT NOT NULL,
    idCliente_FK            INT NOT NULL,
    idTiempo_FK             INT NOT NULL,
    idTransporte_FK         INT NOT NULL,

    -- Claves de la orden (dimension degenerada)
    idOrder                 INT NOT NULL,
    idOrder_Item            INT NOT NULL,

    -- Medidas
    Cantidad_Pedido         INT,
    Ventas                  DECIMAL(12,2),
    Ganancia                DECIMAL(12,2),
    Dias_Envio_Real         INT,
    Dias_Envio_Programado   INT,
    Entrega_Tardia          INT,   -- 1 = llego tarde, 0 = no (viene de Late_delivery_risk)

-- 4. CLAVE PRIMARIA Y CLAVES FORANEAS

    CONSTRAINT PK_Hechos_Entregas
        PRIMARY KEY (idOrder, idOrder_Item),

    CONSTRAINT FK_Hechos_Producto
        FOREIGN KEY (idProducto_FK)  REFERENCES Dimension_Producto(idProducto),

    CONSTRAINT FK_Hechos_Ubicacion
        FOREIGN KEY (idUbicacion_FK) REFERENCES Dimension_Ubicacion(idUbicacion),

    CONSTRAINT FK_Hechos_Cliente
        FOREIGN KEY (idCliente_FK)   REFERENCES Dimension_Cliente(idCliente),

    CONSTRAINT FK_Hechos_Tiempo
        FOREIGN KEY (idTiempo_FK)    REFERENCES Dimension_Tiempo(idTiempo),

    CONSTRAINT FK_Hechos_Transporte
        FOREIGN KEY (idTransporte_FK) REFERENCES Dimension_Transporte(idTransporte)
);
GO


-- VERIFICACION (para las capturas de pantalla del informe)

-- Tablas creadas
SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;

-- Claves primarias y foraneas
SELECT
    tc.TABLE_NAME,
    tc.CONSTRAINT_TYPE,
    tc.CONSTRAINT_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
WHERE tc.CONSTRAINT_TYPE IN ('PRIMARY KEY', 'FOREIGN KEY')
ORDER BY tc.TABLE_NAME, tc.CONSTRAINT_TYPE;
GO
