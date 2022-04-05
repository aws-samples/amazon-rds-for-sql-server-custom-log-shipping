
/*********************************PLEASE READ THIS BEFORE YOU PROCEED*****************************************/
/***************DO NOT RUN THIS SCRIPT ON SECONDARY, THIS SCRIPT ONLY TO BE RUN ON PRIMARY********************/

USE [dbmig]
GO

/****** Object:  StoredProcedure [dbo].[uspManagePrimaryLSTracking]    Script Date: 1/1/2022 6:38:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspManagePrimaryLSTracking]
(
		@ListofDBs NVARCHAR(MAX) -- Enter your database name as comma separated
	
)
/***********Author - Rajib Sadhu**************/
/*
EXEC dbo.uspManagePrimaryLSTracking 'AdventureWorks2019,AdventureWorksDW2019,pubs2,TEST_1'
*/
AS
BEGIN		
	SET NOCOUNT ON

	DECLARE @cmd NVARCHAR(1000)
	DECLARE @LiCounter INT = 1
	DECLARE @LiMaxCount INT
	DECLARE @LsDatabaseName SYSNAME
	DECLARE @FullBackupCheckpointLSN NUMERIC(25, 0)
	DECLARE @BackupSetId INT

	/*****************Parse the comma separated database names****************/

	CREATE TABLE #DBList
	(
		DatabaseId	INT IDENTITY(1,1),
		DatabaseName SYSNAME
	)

	DECLARE @DbListXML XML = CAST('<root><U>'+ Replace(@ListofDBs, ',', '</U><U>')+ '</U></root>' AS XML)
    
	INSERT INTO #DBList (DatabaseName)

	SELECT f.x.value('.', 'SYSNAME') AS user_id
	FROM @DbListXML.nodes('/root/U') f(x)
    

	/************Populate Full Backup and Tran Log information*****************/

	SET @LiCounter = 1

	WHILE(1=1)
	BEGIN
			SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

			IF(@LiCounter <= @LiMaxCount)
			BEGIN
					SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter
						
					---Populate full backup information

					IF NOT EXISTS(SELECT 1 FROM [RDSDBServer].[dbmig].[dbo].[tblLSTracking] WHERE [database_name] = @LsDatabaseName AND [backup_type] = 'Database')
					BEGIN
					
						INSERT INTO [RDSDBServer].[dbmig].[dbo].[tblLSTracking]
								   ([Server]
								   ,[database_name]
								   ,[backup_start_date]
								   ,[backup_finish_date]
								   ,[backup_type]
								   ,[backup_size]
								   ,[physical_device_name]
								   ,[file_name]
								   ,[backupset_name]
								   ,[processing_status]
								   ,[backup_set_id]
								   ,[checkpoint_lsn]
								   ,[database_backup_lsn])


						SELECT		TOP 1
									CONVERT(CHAR(100), SERVERPROPERTY('Servername')) AS Server, 
									bs.database_name, 
									bs.backup_start_date, 
									bs.backup_finish_date, 
									CASE	bs.type 
										WHEN 'D' THEN 'Database' 
										WHEN 'L' THEN 'Log' 
										END AS backup_type, 
									bs.backup_size, 
									bmf.physical_device_name, 
									bs.database_name + '_fullbackup.bak',
									bs.name as backupset_name,
									NULL,
									bs.backup_set_id,
									bs.checkpoint_lsn,
									bs.database_backup_lsn


						FROM		msdb.dbo.backupmediafamily bmf
						INNER JOIN	msdb.dbo.backupset bs
						ON			bmf.media_set_id = bs.media_set_id 
						WHERE		bs.database_name = @LsDatabaseName
						AND			bs.type = 'D'
						AND			bs.name = bs.database_name + '-Full Database Backup'
						ORDER BY	bs.backup_finish_date DESC

					END

					
					--Populate tran log backup information

					SELECT @FullBackupCheckpointLSN = [checkpoint_lsn] FROM [RDSDBServer].[dbmig].[dbo].[tblLSTracking] WHERE [database_name] = @LsDatabaseName AND [backup_type] = 'Database'

					SELECT @BackupSetId = COALESCE(MAX([backup_set_id]),0) FROM [RDSDBServer].[dbmig].[dbo].[tblLSTracking] WHERE [database_name] = @LsDatabaseName AND [backup_type] = 'Log'

					
					INSERT INTO [RDSDBServer].[dbmig].[dbo].[tblLSTracking]
							   ([Server]
							   ,[database_name]
							   ,[backup_start_date]
							   ,[backup_finish_date]
							   ,[backup_type]
							   ,[backup_size]
							   ,[physical_device_name]
							   ,[file_name]
							   ,[backupset_name]
							   ,[processing_status]  
							   ,[backup_set_id]
							   ,[checkpoint_lsn]
							   ,[database_backup_lsn])

					SELECT 
								CONVERT(CHAR(100), SERVERPROPERTY('Servername')) AS Server, 
								bs.database_name, 
								bs.backup_start_date, 
								bs.backup_finish_date, 
								CASE	bs.type 
									WHEN 'D' THEN 'Database' 
									WHEN 'L' THEN 'Log' 
									END AS backup_type, 
								bs.backup_size, 
								bmf.physical_device_name, 
								SUBSTRING(bmf.physical_device_name, CHARINDEX(bs.database_name + '_', bmf.physical_device_name), LEN(bmf.physical_device_name)),
								bs.name as backupset_name,
								NULL,
								bs.backup_set_id,
								bs.checkpoint_lsn,
								bs.database_backup_lsn
	

					FROM		msdb.dbo.backupmediafamily bmf
					INNER JOIN	msdb.dbo.backupset bs
					ON			bmf.media_set_id = bs.media_set_id 
					WHERE		bs.database_name = @LsDatabaseName
					AND			bs.type = 'L'
					AND			((@BackupSetId = 0 AND bs.backup_set_id > @BackupSetId AND bs.database_backup_lsn = @FullBackupCheckpointLSN)
														OR
								(@BackupSetId <> 0 AND bs.backup_set_id > @BackupSetId))
					ORDER BY	bs.database_name, bs.backup_finish_date ASC


					SET @LiCounter = @LiCounter +1
			END
			ElSE
			BEGIN
					BREAK
			END

	END --WHILE(1=1)


	DROP TABLE #DBList

	SET NOCOUNT OFF
END