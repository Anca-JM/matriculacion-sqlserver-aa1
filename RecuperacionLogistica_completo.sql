/* ##########################################################################
   RecuperacionLogistica - Script completo
   Administración de Bases de Datos - Unidad 2, Tema 1: Fundamentos de recuperación
   Autor: Marquez Villarroel Jafet Eliut - UNACH, Cuarto Semestre "A" (2026-2S)
   Motor: SQL Server 2022 Express  |  Herramienta: SQL Server Management Studio 22
   Orden de ejecución: bloques 1 a 6. Los casos de concurrencia (bloque 3) se
   ejecutan en DOS ventanas de consulta a la vez (operador A y operador B).
   ########################################################################## */

/* ===== BLOQUE 1: base de datos, tablas, restricciones y trigger de capacidad ===== */
/* =====================================================================
   RecuperacionLogistica - Paso 1: base de datos, tablas y restricciones
   ===================================================================== */
USE master;
GO
IF DB_ID('RecuperacionLogistica') IS NOT NULL
BEGIN
    ALTER DATABASE RecuperacionLogistica SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE RecuperacionLogistica;
END
GO
CREATE DATABASE RecuperacionLogistica;
GO
-- Modelo FULL: necesario para respaldar el log y recuperar a un punto en el tiempo
ALTER DATABASE RecuperacionLogistica SET RECOVERY FULL;
GO
USE RecuperacionLogistica;
GO

CREATE TABLE dbo.Sucursales (
    id_sucursal      INT           NOT NULL,
    nombre_ciudad    NVARCHAR(60)  NOT NULL,
    capacidad_maxima INT           NOT NULL,
    CONSTRAINT PK_Sucursales PRIMARY KEY (id_sucursal),
    CONSTRAINT UQ_Sucursales_Ciudad UNIQUE (nombre_ciudad),
    CONSTRAINT CK_Sucursales_Capacidad CHECK (capacidad_maxima > 0)
);
GO

CREATE TABLE dbo.Paquetes (
    id_paquete   INT IDENTITY(1,1) NOT NULL,
    descripcion  NVARCHAR(120)  NOT NULL,
    peso         DECIMAL(8,2)   NOT NULL,
    costo_envio  DECIMAL(10,2)  NOT NULL,
    id_sucursal  INT            NOT NULL,
    estado       NVARCHAR(15)   NOT NULL CONSTRAINT DF_Paquetes_Estado DEFAULT ('Registrado'),
    fecha_envio  DATE           NOT NULL CONSTRAINT DF_Paquetes_Fecha DEFAULT (CAST(GETDATE() AS DATE)),
    CONSTRAINT PK_Paquetes PRIMARY KEY (id_paquete),
    CONSTRAINT FK_Paquetes_Sucursales FOREIGN KEY (id_sucursal) REFERENCES dbo.Sucursales (id_sucursal),
    CONSTRAINT CK_Paquetes_Peso  CHECK (peso > 0),
    CONSTRAINT CK_Paquetes_Costo CHECK (costo_envio > 0),
    CONSTRAINT CK_Paquetes_Estado CHECK (estado IN ('Registrado', 'En ruta', 'Entregado', 'Devuelto'))
);
GO

/* Regla que una CHECK no puede expresar porque compara contra otras filas:
   una sucursal no puede tener más paquetes pendientes (no entregados) que su capacidad máxima. */
CREATE TRIGGER dbo.tr_Paquetes_CapacidadSucursal
ON dbo.Paquetes
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM dbo.Sucursales AS s
        JOIN (SELECT DISTINCT id_sucursal FROM inserted) AS i ON i.id_sucursal = s.id_sucursal
        CROSS APPLY (SELECT COUNT(*) AS pendientes
                     FROM dbo.Paquetes AS p
                     WHERE p.id_sucursal = s.id_sucursal AND p.estado IN ('Registrado', 'En ruta')) AS c
        WHERE c.pendientes > s.capacidad_maxima
    )
    BEGIN
        THROW 50010, 'La sucursal superaría su capacidad máxima de paquetes pendientes.', 1;
    END
END;
GO

INSERT INTO dbo.Sucursales (id_sucursal, nombre_ciudad, capacidad_maxima) VALUES
    (1, N'Riobamba', 8), (2, N'Quito', 20), (3, N'Guayaquil', 20), (4, N'Cuenca', 10);

INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal, estado, fecha_envio) VALUES
    (N'Laptop',            2.50, 12.50, 1, 'Registrado', '2026-11-02'),
    (N'Caja de libros',    8.00, 18.00, 1, 'En ruta',    '2026-11-02'),
    (N'Teléfono celular',  0.40,  6.00, 2, 'Registrado', '2026-11-03'),
    (N'Repuestos de auto', 12.75, 25.00, 3, 'En ruta',    '2026-11-03'),
    (N'Medicinas',          1.20,  9.50, 2, 'Entregado',  '2026-11-04'),
    (N'Ropa',               3.00, 10.00, 4, 'Registrado', '2026-11-04'),
    (N'Impresora',          6.30, 15.75, 3, 'Registrado', '2026-11-05'),
    (N'Documentos',         0.20,  4.00, 1, 'Entregado',  '2026-11-05'),
    (N'Televisor 43"',     11.00, 28.00, 4, 'En ruta',    '2026-11-06'),
    (N'Herramientas',       9.40, 20.00, 2, 'Registrado', '2026-11-06');
GO

SELECT s.id_sucursal, s.nombre_ciudad, s.capacidad_maxima,
       COUNT(p.id_paquete) AS paquetes
FROM dbo.Sucursales AS s
LEFT JOIN dbo.Paquetes AS p ON p.id_sucursal = s.id_sucursal
GROUP BY s.id_sucursal, s.nombre_ciudad, s.capacidad_maxima
ORDER BY s.id_sucursal;

SELECT OBJECT_NAME(parent_object_id) AS tabla, name AS restriccion, type_desc AS tipo
FROM sys.objects
WHERE type IN ('PK', 'F', 'C', 'UQ', 'TR') AND OBJECT_NAME(parent_object_id) IN ('Sucursales', 'Paquetes')
ORDER BY tabla, tipo;
GO
GO

/* ===== BLOQUE 2: pruebas de consistencia (inserciones válidas e inválidas) ===== */
/* =====================================================================
   Paso 2: inserciones válidas e inválidas (el motor debe bloquear las inválidas)
   ===================================================================== */
USE RecuperacionLogistica;
GO
SET NOCOUNT ON;
DECLARE @pruebas TABLE (prueba NVARCHAR(60), resultado NVARCHAR(12), error INT, mensaje NVARCHAR(200));

-- 1) Válida
BEGIN TRY
    INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES (N'Tablet', 0.80, 7.50, 4);
    INSERT INTO @pruebas VALUES (N'1. Válido (Cuenca)', N'ACEPTADO', NULL, NULL);
END TRY
BEGIN CATCH
    INSERT INTO @pruebas VALUES (N'1. Válido (Cuenca)', N'BLOQUEADO', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- 2) Peso negativo
BEGIN TRY
    INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES (N'Caja', -3.00, 8.00, 1);
    INSERT INTO @pruebas VALUES (N'2. Peso -3', N'ACEPTADO', NULL, NULL);
END TRY
BEGIN CATCH
    INSERT INTO @pruebas VALUES (N'2. Peso -3', N'BLOQUEADO', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- 3) Costo de envío cero
BEGIN TRY
    INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES (N'Sobre', 0.10, 0.00, 2);
    INSERT INTO @pruebas VALUES (N'3. Costo 0', N'ACEPTADO', NULL, NULL);
END TRY
BEGIN CATCH
    INSERT INTO @pruebas VALUES (N'3. Costo 0', N'BLOQUEADO', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- 4) Sucursal inexistente
BEGIN TRY
    INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES (N'Bicicleta', 14.00, 30.00, 99);
    INSERT INTO @pruebas VALUES (N'4. Sucursal 99', N'ACEPTADO', NULL, NULL);
END TRY
BEGIN CATCH
    INSERT INTO @pruebas VALUES (N'4. Sucursal 99', N'BLOQUEADO', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- 5) Capacidad: Riobamba admite 8 pendientes y tiene 2; se intentan 7 de golpe (llegaría a 9)
BEGIN TRY
    INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
    SELECT N'Lote ' + CAST(n AS NVARCHAR(3)), 1.00, 5.00, 1
    FROM (VALUES (1),(2),(3),(4),(5),(6),(7)) AS v(n);
    INSERT INTO @pruebas VALUES (N'5. Lote de 7 (capacidad)', N'ACEPTADO', NULL, NULL);
END TRY
BEGIN CATCH
    INSERT INTO @pruebas VALUES (N'5. Lote de 7 (capacidad)', N'BLOQUEADO', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- 6) Dentro de una transacción: una fila buena y una mala -> no debe quedar ninguna
BEGIN TRY
    BEGIN TRANSACTION;
        INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES (N'Monitor', 4.00, 11.00, 3);
        INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES (N'Silla', 5.00, -2.00, 3);
    COMMIT TRANSACTION;
    INSERT INTO @pruebas VALUES (N'6. Transacción mixta', N'ACEPTADO', NULL, NULL);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @pruebas VALUES (N'6. Transacción mixta', N'BLOQUEADO', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

SELECT prueba, resultado, error,
       CASE WHEN CHARINDEX('"', mensaje) > 0
            THEN SUBSTRING(mensaje, CHARINDEX('"', mensaje) + 1, CHARINDEX('"', mensaje, CHARINDEX('"', mensaje) + 1) - CHARINDEX('"', mensaje) - 1)
            ELSE ISNULL(LEFT(mensaje, 34), '-') END AS bloqueado_por
FROM @pruebas;

SELECT COUNT(*) AS total_paquetes,
       SUM(CASE WHEN descripcion = N'Monitor' THEN 1 ELSE 0 END) AS monitor_guardado,
       SUM(CASE WHEN descripcion LIKE N'Lote %' THEN 1 ELSE 0 END) AS lote_guardado
FROM dbo.Paquetes;
GO
GO

/* ===== BLOQUE 3: control de concurrencia =====
   Antes de cada caso ejecutar este restablecimiento. Luego abrir dos ventanas:
   Caso 1: ventana A = A1, ventana B = B1 (iniciar A primero).
   Caso 2: ventana B = B2 (RC y luego RR), ventana A = A2 (iniciar B primero).
   Caso 3: ventana B = B3 (RR y luego SERIALIZABLE), ventana A = A3 (iniciar B primero). */
/* Deja los datos como al inicio antes de cada escenario de concurrencia. */
USE RecuperacionLogistica;
SET NOCOUNT ON;
UPDATE dbo.Paquetes SET costo_envio = 12.50 WHERE id_paquete = 1;
DELETE FROM dbo.Paquetes WHERE descripcion = N'Paquete urgente';
SELECT 'Datos restablecidos' AS estado, (SELECT costo_envio FROM dbo.Paquetes WHERE id_paquete = 1) AS costo_paquete_1,
       (SELECT COUNT(*) FROM dbo.Paquetes WHERE id_sucursal = 1 AND estado IN ('Registrado', 'En ruta')) AS pendientes_riobamba;
GO

/* --- Caso 1, ventana A --- */
/* Concurrencia - Caso 1 (lectura sucia). OPERADOR A: cambia el costo y NO confirma durante 15 s. */
USE RecuperacionLogistica;
SET NOCOUNT ON;
SELECT 'A: inicio' AS evento, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora;
BEGIN TRANSACTION;
    UPDATE dbo.Paquetes SET costo_envio = 99.99 WHERE id_paquete = 1;
    SELECT 'A: costo cambiado a 99.99 (sin COMMIT)' AS evento, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora;
    WAITFOR DELAY '00:00:15';
ROLLBACK TRANSACTION;   -- el operador se arrepiente: el 99.99 nunca existió
SELECT 'A: ROLLBACK' AS evento, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora, costo_envio AS costo_final
FROM dbo.Paquetes WHERE id_paquete = 1;
GO

/* --- Caso 1, ventana B --- */
/* Concurrencia - Caso 1 (lectura sucia). OPERADOR B: lee el mismo paquete mientras A no confirma. */
USE RecuperacionLogistica;
SET NOCOUNT ON;
DECLARE @t0 DATETIME2, @costo DECIMAL(10,2);

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET @t0 = SYSDATETIME();
SELECT @costo = costo_envio FROM dbo.Paquetes WHERE id_paquete = 1;
SELECT 'B: READ UNCOMMITTED' AS nivel, @costo AS costo_leido,
       DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS espera_ms, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora;

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET @t0 = SYSDATETIME();
SELECT @costo = costo_envio FROM dbo.Paquetes WHERE id_paquete = 1;   -- espera a que A termine
SELECT 'B: READ COMMITTED' AS nivel, @costo AS costo_leido,
       DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS espera_ms, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora;
GO

/* --- Caso 2, ventana B (READ COMMITTED) --- */
/* Concurrencia - Caso 2 (lectura no repetible). OPERADOR B: reporte de Riobamba leído dos veces en la misma transacción (READ COMMITTED). */
USE RecuperacionLogistica;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;
    SELECT 'B: 1.ª lectura' AS lectura, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora,
           SUM(costo_envio) AS total_costos_riobamba, MAX(CASE WHEN id_paquete = 1 THEN costo_envio END) AS costo_paquete_1
    FROM dbo.Paquetes WHERE id_sucursal = 1;
    SELECT 'B: bloqueos que mantengo' AS info, resource_type, request_mode, COUNT(*) AS cantidad
    FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID AND resource_database_id = DB_ID() AND resource_type <> 'DATABASE'
    GROUP BY resource_type, request_mode;
    WAITFOR DELAY '00:00:15';
    SELECT 'B: 2.ª lectura' AS lectura, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora,
           SUM(costo_envio) AS total_costos_riobamba, MAX(CASE WHEN id_paquete = 1 THEN costo_envio END) AS costo_paquete_1
    FROM dbo.Paquetes WHERE id_sucursal = 1;
COMMIT TRANSACTION;
SELECT 'B: COMMIT' AS evento, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora;
GO

/* --- Caso 2, ventana B (REPEATABLE READ) --- */
/* Concurrencia - Caso 2 (lectura no repetible). OPERADOR B: reporte de Riobamba leído dos veces en la misma transacción (REPEATABLE READ). */
USE RecuperacionLogistica;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;
    SELECT 'B: 1.ª lectura' AS lectura, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora,
           SUM(costo_envio) AS total_costos_riobamba, MAX(CASE WHEN id_paquete = 1 THEN costo_envio END) AS costo_paquete_1
    FROM dbo.Paquetes WHERE id_sucursal = 1;
    SELECT 'B: bloqueos que mantengo' AS info, resource_type, request_mode, COUNT(*) AS cantidad
    FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID AND resource_database_id = DB_ID() AND resource_type <> 'DATABASE'
    GROUP BY resource_type, request_mode;
    WAITFOR DELAY '00:00:15';
    SELECT 'B: 2.ª lectura' AS lectura, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora,
           SUM(costo_envio) AS total_costos_riobamba, MAX(CASE WHEN id_paquete = 1 THEN costo_envio END) AS costo_paquete_1
    FROM dbo.Paquetes WHERE id_sucursal = 1;
COMMIT TRANSACTION;
SELECT 'B: COMMIT' AS evento, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora;
GO

/* --- Caso 2, ventana A --- */
/* Concurrencia - Caso 2. OPERADOR A: sube el costo del paquete 1 mientras B genera su reporte. */
USE RecuperacionLogistica;
SET NOCOUNT ON;
DECLARE @t0 DATETIME2 = SYSDATETIME();
UPDATE dbo.Paquetes SET costo_envio = 15.00 WHERE id_paquete = 1;   -- se confirma solo (autocommit)
SELECT 'A: costo actualizado a 15.00 y confirmado' AS evento,
       DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS espera_ms, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora;
GO

/* --- Caso 3, ventana B (REPEATABLE READ) --- */
/* Concurrencia - Caso 3 (lectura fantasma). OPERADOR B: cuenta los paquetes pendientes de Riobamba dos veces (REPEATABLE READ). */
USE RecuperacionLogistica;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;
    SELECT 'B: 1.er conteo' AS conteo, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora, COUNT(*) AS pendientes_riobamba
    FROM dbo.Paquetes WHERE id_sucursal = 1 AND estado IN ('Registrado', 'En ruta');
    SELECT 'B: bloqueos que mantengo' AS info, resource_type, request_mode, COUNT(*) AS cantidad
    FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID AND resource_database_id = DB_ID() AND resource_type <> 'DATABASE'
    GROUP BY resource_type, request_mode;
    WAITFOR DELAY '00:00:15';
    SELECT 'B: 2.º conteo' AS conteo, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora, COUNT(*) AS pendientes_riobamba
    FROM dbo.Paquetes WHERE id_sucursal = 1 AND estado IN ('Registrado', 'En ruta');
COMMIT TRANSACTION;
SELECT 'B: COMMIT' AS evento, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora;
GO

/* --- Caso 3, ventana B (SERIALIZABLE) --- */
/* Concurrencia - Caso 3 (lectura fantasma). OPERADOR B: cuenta los paquetes pendientes de Riobamba dos veces (SERIALIZABLE). */
USE RecuperacionLogistica;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;
    SELECT 'B: 1.er conteo' AS conteo, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora, COUNT(*) AS pendientes_riobamba
    FROM dbo.Paquetes WHERE id_sucursal = 1 AND estado IN ('Registrado', 'En ruta');
    SELECT 'B: bloqueos que mantengo' AS info, resource_type, request_mode, COUNT(*) AS cantidad
    FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID AND resource_database_id = DB_ID() AND resource_type <> 'DATABASE'
    GROUP BY resource_type, request_mode;
    WAITFOR DELAY '00:00:15';
    SELECT 'B: 2.º conteo' AS conteo, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora, COUNT(*) AS pendientes_riobamba
    FROM dbo.Paquetes WHERE id_sucursal = 1 AND estado IN ('Registrado', 'En ruta');
COMMIT TRANSACTION;
SELECT 'B: COMMIT' AS evento, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora;
GO

/* --- Caso 3, ventana A --- */
/* Concurrencia - Caso 3. OPERADOR A: registra un paquete nuevo en Riobamba mientras B cuenta. */
USE RecuperacionLogistica;
SET NOCOUNT ON;
DECLARE @t0 DATETIME2 = SYSDATETIME();
INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal) VALUES (N'Paquete urgente', 2.00, 9.00, 1);
SELECT 'A: paquete nuevo insertado y confirmado' AS evento,
       DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS espera_ms, CONVERT(VARCHAR(12), SYSDATETIME(), 114) AS hora;
GO

/* ===== BLOQUE 4: respaldos completo, diferencial y de log ===== */
/* =====================================================================
   Paso 4: política de respaldos  FULL -> DIFERENCIAL -> LOG
   Carpeta: la de respaldos de la instancia (SQL Server tiene permiso de escritura ahí)
   ===================================================================== */
USE master;
GO
SET NOCOUNT ON;
DECLARE @dir NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(200)) + N'\RecuperacionLogistica';
EXEC master.dbo.xp_create_subdir @dir;

DECLARE @full NVARCHAR(400) = @dir + N'\RL_full.bak',
        @dif  NVARCHAR(400) = @dir + N'\RL_dif.bak',
        @log1 NVARCHAR(400) = @dir + N'\RL_log1.trn',
        @log2 NVARCHAR(400) = @dir + N'\RL_log2.trn';

-- 1) FULL: copia completa, base de toda la cadena
BACKUP DATABASE RecuperacionLogistica TO DISK = @full
    WITH INIT, CHECKSUM, NAME = N'RL Full', STATS = 50;

-- Movimiento del día después del full
INSERT INTO RecuperacionLogistica.dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Cámara fotográfica', 1.10, 8.75, 2), (N'Microondas', 13.50, 26.00, 3);

-- 2) DIFERENCIAL: solo lo que cambió desde el último FULL
BACKUP DATABASE RecuperacionLogistica TO DISK = @dif
    WITH DIFFERENTIAL, INIT, CHECKSUM, NAME = N'RL Diferencial', STATS = 50;

-- Más movimiento
INSERT INTO RecuperacionLogistica.dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Bocinas', 4.20, 12.00, 4);

-- 3) LOG: historial de transacciones (permite volver a un punto exacto en el tiempo)
BACKUP LOG RecuperacionLogistica TO DISK = @log1 WITH INIT, CHECKSUM, NAME = N'RL Log 1';

INSERT INTO RecuperacionLogistica.dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES (N'Guitarra', 3.50, 14.00, 2);
BACKUP LOG RecuperacionLogistica TO DISK = @log2 WITH INIT, CHECKSUM, NAME = N'RL Log 2';
GO

-- Historial que guarda SQL Server de cada respaldo (msdb)
SELECT b.name AS respaldo,
       CASE b.type WHEN 'D' THEN 'Completo' WHEN 'I' THEN 'Diferencial' WHEN 'L' THEN 'Log' END AS tipo,
       CONVERT(VARCHAR(8), b.backup_finish_date, 108) AS hora,
       CAST(b.backup_size / 1024.0 AS DECIMAL(10,1)) AS tamano_KB,
       b.first_lsn, b.last_lsn, b.differential_base_lsn AS base_dif_lsn,
       RIGHT(m.physical_device_name, 12) AS archivo
FROM msdb.dbo.backupset AS b
JOIN msdb.dbo.backupmediafamily AS m ON m.media_set_id = b.media_set_id
WHERE b.database_name = 'RecuperacionLogistica'
  AND b.backup_finish_date >= DATEADD(MINUTE, -10, GETDATE())
ORDER BY b.backup_finish_date;
GO
GO

/* ===== BLOQUE 5: prueba de restauración en una base aparte (punto en el tiempo) ===== */
/* =====================================================================
   Paso 5: prueba de restauración sin tocar producción
   Simulo un borrado accidental, respaldo el log y restauro la cadena en una base
   APARTE (RecuperacionLogistica_Prueba) hasta un segundo antes del error.
   ===================================================================== */
USE master;
GO
SET NOCOUNT ON;
DECLARE @dir NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(200)) + N'\RecuperacionLogistica';
DECLARE @data NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(200));

-- Estado correcto antes del error
DECLARE @antes INT = (SELECT COUNT(*) FROM RecuperacionLogistica.dbo.Paquetes);
DECLARE @punto DATETIME = GETDATE();          -- último momento bueno
WAITFOR DELAY '00:00:02';

-- Error humano: alguien borra todos los paquetes de Guayaquil
DELETE FROM RecuperacionLogistica.dbo.Paquetes WHERE id_sucursal = 3;
DECLARE @despues INT = (SELECT COUNT(*) FROM RecuperacionLogistica.dbo.Paquetes);

-- Respaldo del log que contiene el borrado (sin él no se puede llegar al punto exacto)
DECLARE @log3 NVARCHAR(400) = @dir + N'\RL_log3.trn';
BACKUP LOG RecuperacionLogistica TO DISK = @log3 WITH INIT, CHECKSUM, NAME = N'RL Log 3';

-- 1) ¿Los archivos están sanos?
DECLARE @full NVARCHAR(400) = @dir + N'\RL_full.bak';
RESTORE VERIFYONLY FROM DISK = @full WITH CHECKSUM;

-- 2) Restaurar la cadena en una base de prueba (nombre y archivos distintos)
IF DB_ID('RecuperacionLogistica_Prueba') IS NOT NULL
BEGIN
    ALTER DATABASE RecuperacionLogistica_Prueba SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE RecuperacionLogistica_Prueba;
END;
DECLARE @mdf NVARCHAR(400) = @data + N'RL_Prueba.mdf', @ldf NVARCHAR(400) = @data + N'RL_Prueba_log.ldf';
DECLARE @dif NVARCHAR(400) = @dir + N'\RL_dif.bak', @log1 NVARCHAR(400) = @dir + N'\RL_log1.trn', @log2 NVARCHAR(400) = @dir + N'\RL_log2.trn';
DECLARE @t0 DATETIME2 = SYSDATETIME();

RESTORE DATABASE RecuperacionLogistica_Prueba FROM DISK = @full
    WITH MOVE 'RecuperacionLogistica' TO @mdf, MOVE 'RecuperacionLogistica_log' TO @ldf, NORECOVERY, REPLACE;
RESTORE DATABASE RecuperacionLogistica_Prueba FROM DISK = @dif WITH NORECOVERY;
RESTORE LOG RecuperacionLogistica_Prueba FROM DISK = @log1 WITH NORECOVERY;
RESTORE LOG RecuperacionLogistica_Prueba FROM DISK = @log2 WITH NORECOVERY;
RESTORE LOG RecuperacionLogistica_Prueba FROM DISK = @log3 WITH STOPAT = @punto, RECOVERY;   -- punto en el tiempo

DECLARE @rto_ms INT = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());

-- 3) Hallazgos
SELECT 'Producción antes del error' AS base, @antes AS paquetes
UNION ALL SELECT 'Producción después del borrado', @despues
UNION ALL SELECT 'Prueba restaurada (STOPAT)', (SELECT COUNT(*) FROM RecuperacionLogistica_Prueba.dbo.Paquetes);

SELECT p.id_paquete, p.descripcion, p.costo_envio, s.nombre_ciudad
FROM RecuperacionLogistica_Prueba.dbo.Paquetes AS p
JOIN RecuperacionLogistica_Prueba.dbo.Sucursales AS s ON s.id_sucursal = p.id_sucursal
WHERE p.id_sucursal = 3;

SELECT CONVERT(VARCHAR(19), @punto, 120) AS restaurado_hasta, @rto_ms AS tiempo_restauracion_ms;
GO
DBCC CHECKDB ('RecuperacionLogistica_Prueba') WITH NO_INFOMSGS;
SELECT 'CHECKDB sin errores' AS integridad;
GO
GO

/* ===== BLOQUE 6: lo que agregué (función de tabla vs. vista e índice medido) ===== */
/* =====================================================================
   Lo que agregué: reporte parametrizado (función de tabla) frente a una vista,
   e índice para ese reporte medido con 20 000 paquetes (todo dentro de una
   transacción que se revierte, para no ensuciar la base).
   ===================================================================== */
USE RecuperacionLogistica;
GO
CREATE OR ALTER VIEW dbo.Vista_PaquetesDetalle AS
SELECT p.id_paquete, p.descripcion, p.peso, p.costo_envio, p.estado, p.fecha_envio,
       s.id_sucursal, s.nombre_ciudad
FROM dbo.Paquetes AS p
JOIN dbo.Sucursales AS s ON s.id_sucursal = p.id_sucursal;
GO
CREATE OR ALTER FUNCTION dbo.fn_PaquetesPorFechaSucursal (@desde DATE, @hasta DATE, @id_sucursal INT)
RETURNS TABLE
AS
RETURN
    SELECT p.id_paquete, p.descripcion, p.peso, p.costo_envio, p.estado, p.fecha_envio, s.nombre_ciudad
    FROM dbo.Paquetes AS p
    JOIN dbo.Sucursales AS s ON s.id_sucursal = p.id_sucursal
    WHERE p.id_sucursal = @id_sucursal
      AND p.fecha_envio BETWEEN @desde AND @hasta;
GO
SET NOCOUNT ON;
-- Uso normal del reporte: Quito entre el 3 y el 6 de noviembre
SELECT * FROM dbo.fn_PaquetesPorFechaSucursal('2026-11-03', '2026-11-06', 2);

-- La vista no recibe parámetros: devuelve todo y el filtro hay que escribirlo cada vez
SELECT COUNT(*) AS filas_vista_sin_filtro FROM dbo.Vista_PaquetesDetalle;

BEGIN TRANSACTION;
    -- 20 000 paquetes entregados en 2026 (entregados: no cuentan para la capacidad)
    ;WITH n AS (SELECT TOP (20000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS k
                FROM sys.all_objects a CROSS JOIN sys.all_objects b)
    INSERT INTO dbo.Paquetes (descripcion, peso, costo_envio, id_sucursal, estado, fecha_envio)
    SELECT N'Histórico ' + CAST(k AS NVARCHAR(6)), 1 + k % 20, 3 + k % 30, 1 + k % 4, 'Entregado',
           DATEADD(DAY, k % 300, '2026-01-01')
    FROM n;

    -- Sin índice
    SET STATISTICS IO ON;
    SELECT COUNT(*) AS marzo_quito_sin_indice FROM dbo.fn_PaquetesPorFechaSucursal('2026-03-01', '2026-03-31', 2);
    SET STATISTICS IO OFF;

    CREATE INDEX IX_Paquetes_Sucursal_Fecha ON dbo.Paquetes (id_sucursal, fecha_envio)
        INCLUDE (descripcion, peso, costo_envio, estado);

    SET STATISTICS IO ON;
    SELECT COUNT(*) AS marzo_quito_con_indice FROM dbo.fn_PaquetesPorFechaSucursal('2026-03-01', '2026-03-31', 2);
    SET STATISTICS IO OFF;
ROLLBACK TRANSACTION;   -- se deshacen las 20 000 filas y el índice

SELECT COUNT(*) AS paquetes_despues_del_rollback,
       (SELECT COUNT(*) FROM sys.indexes WHERE name = 'IX_Paquetes_Sucursal_Fecha') AS indice_existe
FROM dbo.Paquetes;
GO
GO

/* ===== Copia de contingencia en la nube (PowerShell, archivo 06_copia_nube.ps1) =====
   1) BACKUP DATABASE RecuperacionLogistica TO DISK = N'C:\Users\Public\Documents\RL_copia_nube.bak'
      WITH COPY_ONLY, INIT, CHECKSUM;   -- COPY_ONLY no rompe la cadena FULL -> DIF -> LOG
   2) Copy-Item a la carpeta sincronizada de Google Drive y comparación del hash SHA-256 (origen = destino).
   Programación sugerida (SQL Server Express no trae el Agente): Programador de tareas de Windows, p. ej.
   schtasks /create /tn "RL_Log_15min" /sc minute /mo 15 /tr "sqlcmd -S localhost\SQLEXPRESS -E -C -i C:\RL\log.sql"
   donde log.sql ejecuta BACKUP LOG con un nombre de archivo que incluye fecha y hora. */
