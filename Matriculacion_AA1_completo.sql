/* ADMINISTRACION DE BASES DE DATOS - Actividad Autonoma U1-T1
   Sistema de Matriculacion Universitaria: gestion de concurrencia y consistencia
   Motor: SQL Server 2022 Express (localhost\SQLEXPRESS)   Autor: Marquez Villarroel Jafet Eliut
   Contenido: 1) Esquema  2) Transacciones A/B/C  3) Niveles de aislamiento (dos sesiones)  4) Valor agregado: sp_Matricular */

/* ======================================================================
   1. ESQUEMA, RESTRICCIONES, INDICE Y DATOS DE PRUEBA
   ====================================================================== */

/* =====================================================================
   ADMINISTRACION DE BASES DE DATOS - Actividad Autonoma U1-T1
   Sistema de Matriculacion Universitaria: concurrencia y consistencia
   Motor: SQL Server 2022 Express (localhost\SQLEXPRESS)
   Bloque 1: creacion del esquema, restricciones, indices y datos de prueba
   ===================================================================== */
USE master;
GO
IF DB_ID('MatriculaDB') IS NOT NULL
BEGIN
    ALTER DATABASE MatriculaDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MatriculaDB;
END
GO
CREATE DATABASE MatriculaDB;
GO
USE MatriculaDB;
GO

/* ---------- Tabla 1: Estudiantes ---------- */
CREATE TABLE Estudiantes (
    estudiante_id INT IDENTITY(1,1) CONSTRAINT PK_Estudiantes PRIMARY KEY,
    nombre        VARCHAR(100) NOT NULL,
    cedula        CHAR(10)     NOT NULL CONSTRAINT UQ_Estudiantes_cedula UNIQUE,
    facultad      VARCHAR(60)  NOT NULL
);

/* ---------- Tabla 2: Asignaturas ----------
   CHECK: el cupo nunca puede ser negativo (integridad de dominio). */
CREATE TABLE Asignaturas (
    asignatura_id     INT IDENTITY(1,1) CONSTRAINT PK_Asignaturas PRIMARY KEY,
    nombre_materia    VARCHAR(80) NOT NULL CONSTRAINT UQ_Asignaturas_nombre UNIQUE,
    docente           VARCHAR(80) NOT NULL,
    cupos_disponibles INT         NOT NULL CONSTRAINT CK_cupos_no_negativos CHECK (cupos_disponibles >= 0)
);

/* ---------- Tabla 3: Registros_Matricula ----------
   FK a Estudiantes y Asignaturas, estado restringido y un estudiante
   no puede matricularse dos veces en la misma materia. */
CREATE TABLE Registros_Matricula (
    registro_id    INT IDENTITY(1,1) CONSTRAINT PK_Registros PRIMARY KEY,
    estudiante_id  INT         NOT NULL CONSTRAINT FK_Reg_Estudiante  FOREIGN KEY REFERENCES Estudiantes(estudiante_id),
    asignatura_id  INT         NOT NULL CONSTRAINT FK_Reg_Asignatura  FOREIGN KEY REFERENCES Asignaturas(asignatura_id),
    fecha_registro DATETIME2(0) NOT NULL CONSTRAINT DF_Reg_fecha DEFAULT SYSDATETIME(),
    estado         VARCHAR(10) NOT NULL CONSTRAINT CK_Reg_estado CHECK (estado IN ('CONFIRMADA','PENDIENTE')),
    CONSTRAINT UQ_Reg_estudiante_materia UNIQUE (estudiante_id, asignatura_id)
);

/* Indice no agrupado: acelera "cuantos inscritos tiene una materia" y las
   uniones por asignatura (mejora propuesta). */
CREATE NONCLUSTERED INDEX IX_Reg_asignatura ON Registros_Matricula (asignatura_id) INCLUDE (estado);
GO

/* ---------- Datos de prueba (ficticios) ---------- */
INSERT INTO Estudiantes (nombre, cedula, facultad) VALUES
 ('Estudiante Uno',    '0600000001', 'Ingenieria'),
 ('Estudiante Dos',    '0600000002', 'Ingenieria'),
 ('Estudiante Tres',   '0600000003', 'Ingenieria'),
 ('Estudiante Cuatro', '0600000004', 'Ingenieria');

INSERT INTO Asignaturas (nombre_materia, docente, cupos_disponibles) VALUES
 ('Base de Datos',      'Docente A', 5),
 ('Machine Learning',   'Docente B', 3),
 ('Metaheuristicas',    'Docente C', 2),
 ('Metodos Numericos',  'Docente D', 4);
GO

SELECT * FROM Estudiantes;
SELECT * FROM Asignaturas;
SELECT * FROM Registros_Matricula;
GO


/* ======================================================================
   2. TRANSACCIONES ACID (A: COMMIT, B: ROLLBACK, C: multimateria, + CHECK)
   ====================================================================== */

/* =====================================================================
   Bloque 2: transacciones con propiedades ACID (escenarios A, B y C)
   ===================================================================== */
USE MatriculaDB;
GO
SET NOCOUNT ON;

/* ---------------- TRANSACCION A: COMMIT ----------------
   Matricula completa del Estudiante 1 en "Base de Datos". */
PRINT '=== ESTADO ANTES (A) ===';
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM Asignaturas WHERE nombre_materia = 'Base de Datos';
SELECT COUNT(*) AS registros_totales FROM Registros_Matricula;

BEGIN TRANSACTION;
    INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado)
    VALUES (1, (SELECT asignatura_id FROM Asignaturas WHERE nombre_materia = 'Base de Datos'), 'CONFIRMADA');

    UPDATE Asignaturas
       SET cupos_disponibles = cupos_disponibles - 1
     WHERE nombre_materia = 'Base de Datos';
COMMIT;

PRINT '=== VERIFICACION DESPUES DEL COMMIT (A) ===';
SELECT registro_id, estudiante_id, asignatura_id, estado FROM Registros_Matricula;
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM Asignaturas WHERE nombre_materia = 'Base de Datos';
GO

/* ---------------- TRANSACCION B: ROLLBACK ----------------
   Simula un fallo a mitad de camino: se hace el INSERT del Estudiante 2,
   se omite el UPDATE de cupos y se revierte. */
PRINT '=== ESTADO ANTES (B) ===';
SELECT COUNT(*) AS registros_antes FROM Registros_Matricula;

BEGIN TRANSACTION;
    INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado)
    VALUES (2, (SELECT asignatura_id FROM Asignaturas WHERE nombre_materia = 'Base de Datos'), 'PENDIENTE');

    PRINT 'Dentro de la transaccion (INSERT hecho, sin confirmar):';
    SELECT COUNT(*) AS registros_dentro_de_la_transaccion FROM Registros_Matricula;
    /* >>> FALLO SIMULADO: el UPDATE de cupos nunca se ejecuta <<< */
ROLLBACK;

PRINT '=== VERIFICACION DESPUES DEL ROLLBACK (B) ===';
SELECT COUNT(*) AS registros_despues FROM Registros_Matricula;
SELECT registro_id, estudiante_id, estado FROM Registros_Matricula;
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM Asignaturas WHERE nombre_materia = 'Base de Datos';
GO

/* ---------------- TRANSACCION C: matricula multimateria ----------------
   Tres UPDATE en una sola transaccion; el tercero apunta a una materia que
   no existe. En SQL Server un UPDATE sobre un ID inexistente NO lanza error
   (afecta 0 filas), por eso se valida @@ROWCOUNT y se fuerza el error con THROW.
   XACT_ABORT ON garantiza el rollback ante cualquier error en tiempo de ejecucion. */
PRINT '=== ESTADO ANTES (C) ===';
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM Asignaturas ORDER BY asignatura_id;

SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
        UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 2;   -- Materia 1 (exito)
        PRINT 'Materia 1 actualizada.  Filas afectadas: ' + CAST(@@ROWCOUNT AS VARCHAR(5));

        UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 3;   -- Materia 2 (exito)
        PRINT 'Materia 2 actualizada.  Filas afectadas: ' + CAST(@@ROWCOUNT AS VARCHAR(5));

        PRINT 'Dentro de la transaccion (antes de fallar):';
        SELECT asignatura_id, nombre_materia, cupos_disponibles FROM Asignaturas WHERE asignatura_id IN (2,3);

        UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 999; -- Materia 3 (no existe)
        IF @@ROWCOUNT = 0
            THROW 50001, 'La asignatura 999 no existe: se cancela toda la matricula.', 1;
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    PRINT 'ERROR CAPTURADO: ' + ERROR_MESSAGE();
    PRINT 'ROLLBACK ejecutado.';
END CATCH;
SET XACT_ABORT OFF;

PRINT '=== VERIFICACION DESPUES DEL ROLLBACK (C): los cupos no cambiaron ===';
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM Asignaturas ORDER BY asignatura_id;
GO

/* ---------------- Consistencia (la C de ACID): el CHECK protege el cupo ----------------
   Intento de dejar un cupo negativo: el motor lo rechaza y la transaccion se revierte. */
BEGIN TRY
    BEGIN TRANSACTION;
        UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 10 WHERE asignatura_id = 3;
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    PRINT 'ERROR ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ': ' + ERROR_MESSAGE();
END CATCH;
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM Asignaturas WHERE asignatura_id = 3;
GO


/* ======================================================================
   3. NIVELES DE AISLAMIENTO - ejecutar SESION 1 y SESION 2 en DOS ventanas al mismo tiempo
   (restablecer antes de cada prueba: UPDATE Asignaturas SET cupos_disponibles=5 WHERE asignatura_id=1; DELETE FROM Registros_Matricula WHERE asignatura_id=1;)
   ====================================================================== */


-- ################ 3.1 READ UNCOMMITTED - lectura sucia ################
-- >>> SESION 1 (d1_RU_s1)
USE MatriculaDB;
SET NOCOUNT ON;
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  BEGIN TRAN + UPDATE: resta 1 cupo (sin COMMIT)';
BEGIN TRANSACTION;
UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 1;
SELECT cupos_disponibles AS cupos_dentro_de_mi_transaccion FROM Asignaturas WHERE asignatura_id = 1;
WAITFOR DELAY '00:00:10';
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  El estudiante cancela: ROLLBACK';
ROLLBACK;
SELECT cupos_disponibles AS cupos_reales_tras_rollback FROM Asignaturas WHERE asignatura_id = 1;
-- >>> SESION 2 (d1_RU_s2)
USE MatriculaDB;
SET NOCOUNT ON;
WAITFOR DELAY '00:00:04';
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Nivel READ UNCOMMITTED: leo los cupos';
SELECT cupos_disponibles AS cupos_leidos_LECTURA_SUCIA FROM Asignaturas WHERE asignatura_id = 1;
WAITFOR DELAY '00:00:09';
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Leo de nuevo despues del ROLLBACK de la Sesion 1';
SELECT cupos_disponibles AS cupos_reales FROM Asignaturas WHERE asignatura_id = 1;

-- ################ 3.2a READ COMMITTED - evita lectura sucia (la Sesion 2 espera) ################
-- >>> SESION 1 (d2a_RC_s1)
USE MatriculaDB;
SET NOCOUNT ON;
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  BEGIN TRAN + UPDATE: resta 1 cupo (sin COMMIT)';
BEGIN TRANSACTION;
UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 1;
SELECT cupos_disponibles AS cupos_dentro_de_mi_transaccion FROM Asignaturas WHERE asignatura_id = 1;
WAITFOR DELAY '00:00:10';
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  El estudiante cancela: ROLLBACK';
ROLLBACK;
SELECT cupos_disponibles AS cupos_reales_tras_rollback FROM Asignaturas WHERE asignatura_id = 1;
-- >>> SESION 2 (d2a_RC_s2)
USE MatriculaDB;
SET NOCOUNT ON;
WAITFOR DELAY '00:00:04';
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
DECLARE @ini DATETIME2 = SYSDATETIME();
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Nivel READ COMMITTED: intento leer los cupos...';
SELECT cupos_disponibles AS cupos_leidos_CONFIRMADOS FROM Asignaturas WHERE asignatura_id = 1;
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Lectura terminada. Espere (ms): ' + CAST(DATEDIFF(MILLISECOND, @ini, SYSDATETIME()) AS VARCHAR(10));

-- ################ 3.2b READ COMMITTED - lectura no repetible ################
-- >>> SESION 1 (d2b_RC_s1)
USE MatriculaDB;
SET NOCOUNT ON;
WAITFOR DELAY '00:00:03';
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Otro estudiante se matricula y confirma (COMMIT)';
BEGIN TRANSACTION;
UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 1;
COMMIT;
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  COMMIT realizado (no tuvo que esperar a la Sesion 2)';
-- >>> SESION 2 (d2b_RC_s2)
USE MatriculaDB;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  READ COMMITTED: primera lectura';
SELECT cupos_disponibles AS primera_lectura FROM Asignaturas WHERE asignatura_id = 1;
WAITFOR DELAY '00:00:08';
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Segunda lectura dentro de la MISMA transaccion';
SELECT cupos_disponibles AS segunda_lectura_NO_REPETIBLE FROM Asignaturas WHERE asignatura_id = 1;
COMMIT;

-- ################ 3.3a REPEATABLE READ - el cupo no cambia y el escritor espera ################
-- >>> SESION 1 (d3a_RR_s1)
USE MatriculaDB;
SET NOCOUNT ON;
WAITFOR DELAY '00:00:03';
DECLARE @ini DATETIME2 = SYSDATETIME();
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Intento restar 1 cupo (UPDATE)...';
UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 1;
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  UPDATE completado tras esperar (ms): ' + CAST(DATEDIFF(MILLISECOND, @ini, SYSDATETIME()) AS VARCHAR(10));
SELECT cupos_disponibles AS cupos_finales FROM Asignaturas WHERE asignatura_id = 1;
-- >>> SESION 2 (d3a_RR_s2)
USE MatriculaDB;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  REPEATABLE READ: primera lectura';
SELECT cupos_disponibles AS primera_lectura FROM Asignaturas WHERE asignatura_id = 1;
WAITFOR DELAY '00:00:10';
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Segunda lectura (mismo dato, misma transaccion)';
SELECT cupos_disponibles AS segunda_lectura_REPETIBLE FROM Asignaturas WHERE asignatura_id = 1;
COMMIT;
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  COMMIT: libero el bloqueo';

-- ################ 3.3b REPEATABLE READ - lectura fantasma ################
-- >>> SESION 1 (d3b_RR_s1)
USE MatriculaDB;
SET NOCOUNT ON;
WAITFOR DELAY '00:00:03';
DECLARE @ini DATETIME2 = SYSDATETIME();
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  INSERT de una matricula nueva en la materia 1...';
INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (3, 1, 'CONFIRMADA');
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  INSERT completado. Espera (ms): ' + CAST(DATEDIFF(MILLISECOND, @ini, SYSDATETIME()) AS VARCHAR(10));
-- >>> SESION 2 (d3b_RR_s2)
USE MatriculaDB;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  REPEATABLE READ: cuento los inscritos';
SELECT COUNT(*) AS inscritos_primera_lectura FROM Registros_Matricula WHERE asignatura_id = 1;
WAITFOR DELAY '00:00:08';
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Cuento de nuevo en la misma transaccion';
SELECT COUNT(*) AS inscritos_segunda_lectura_FANTASMA FROM Registros_Matricula WHERE asignatura_id = 1;
COMMIT;

-- ################ 3.4 SERIALIZABLE - sin fantasmas, la Sesion 1 espera ################
-- >>> SESION 1 (d4_SER_s1)
USE MatriculaDB;
SET NOCOUNT ON;
WAITFOR DELAY '00:00:03';
DECLARE @ini DATETIME2 = SYSDATETIME();
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  INSERT de una matricula nueva en la materia 1...';
INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (3, 1, 'CONFIRMADA');
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  INSERT completado. Espera (ms): ' + CAST(DATEDIFF(MILLISECOND, @ini, SYSDATETIME()) AS VARCHAR(10));
-- >>> SESION 2 (d4_SER_s2)
USE MatriculaDB;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  SERIALIZABLE: cuento los inscritos';
SELECT COUNT(*) AS inscritos_primera_lectura FROM Registros_Matricula WHERE asignatura_id = 1;
WAITFOR DELAY '00:00:08';
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Cuento de nuevo en la misma transaccion';
SELECT COUNT(*) AS inscritos_segunda_lectura_SIN_FANTASMA FROM Registros_Matricula WHERE asignatura_id = 1;
COMMIT;

/* ======================================================================
   4. VALOR AGREGADO: PROCEDIMIENTO sp_Matricular (UPDLOCK) Y PRUEBA CONCURRENTE
   (antes: UPDATE Asignaturas SET cupos_disponibles=1 WHERE asignatura_id=3; DELETE FROM Registros_Matricula WHERE asignatura_id=3;)
   ====================================================================== */

USE MatriculaDB;
SET NOCOUNT ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_Matricular
    @estudiante_id INT, @asignatura_id INT, @demora VARCHAR(8) = '00:00:00'
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
            DECLARE @cupos INT;
            -- UPDLOCK: quien lee el cupo lo reserva; el siguiente espera y luego ve el valor ya actualizado
            SELECT @cupos = cupos_disponibles FROM Asignaturas WITH (UPDLOCK, ROWLOCK) WHERE asignatura_id = @asignatura_id;
            IF @cupos IS NULL THROW 50002, 'La asignatura no existe.', 1;
            IF @cupos <= 0    THROW 50003, 'No hay cupos disponibles.', 1;
            WAITFOR DELAY @demora;   -- simula el tiempo que el estudiante tarda en confirmar
            INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (@estudiante_id, @asignatura_id, 'CONFIRMADA');
            UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = @asignatura_id;
        COMMIT;
        PRINT 'Matricula CONFIRMADA (estudiante ' + CAST(@estudiante_id AS VARCHAR(5)) + ').';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        PRINT 'Matricula RECHAZADA (estudiante ' + CAST(@estudiante_id AS VARCHAR(5)) + '): ' + ERROR_MESSAGE();
    END CATCH
END
GO
-- >>> SESION 1
USE MatriculaDB;
SET NOCOUNT ON;
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Estudiante 3 pide el ULTIMO cupo de Metaheuristicas';
EXEC dbo.sp_Matricular @estudiante_id = 3, @asignatura_id = 3, @demora = '00:00:08';
PRINT '[SESION 1] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Fin';
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM Asignaturas WHERE asignatura_id = 3;
-- >>> SESION 2
USE MatriculaDB;
SET NOCOUNT ON;
WAITFOR DELAY '00:00:02';
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Estudiante 4 pide el mismo cupo al mismo tiempo...';
EXEC dbo.sp_Matricular @estudiante_id = 4, @asignatura_id = 3;
PRINT '[SESION 2] ' + CONVERT(VARCHAR(12), SYSDATETIME(), 114) + '  Fin';
SELECT estudiante_id, asignatura_id, estado FROM Registros_Matricula WHERE asignatura_id = 3;