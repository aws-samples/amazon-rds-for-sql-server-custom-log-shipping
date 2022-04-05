
/*********************************PLEASE READ THIS BEFORE YOU PROCEED*****************************************/
/***************DO NOT RUN THIS SCRIPT ON PRIMARY, THIS SCRIPT ONLY TO BE RUN ON SECONDARY********************/

USE [master]
GO
/****** Object:  Database [dbmig]    Script Date: 1/1/2022 8:51:38 PM ******/
CREATE DATABASE [dbmig]
GO
USE [dbmig]
/****** Object:  Table [dbo].[tblLSTracking]    Script Date: 1/1/2022 8:51:38 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblLSTracking](
	[Server] [char](100) NULL,
	[database_name] [nvarchar](128) NULL,
	[backup_start_date] [datetime] NULL,
	[backup_finish_date] [datetime] NULL,
	[backup_type] [varchar](8) NULL,
	[backup_size] [numeric](20, 0) NULL,
	[physical_device_name] [nvarchar](260) NULL,
	[file_name] [nvarchar](260) NULL,
	[backupset_name] [nvarchar](128) NULL,
	[processing_status] [varchar](30) NULL,
	[backup_set_id] [int] NOT NULL,
	[checkpoint_lsn] [numeric](25, 0) NULL,
	[database_backup_lsn] [numeric](25, 0) NULL
) ON [PRIMARY]
GO
/****** Object:  StoredProcedure [dbo].[uspManageSecondaryCutover]    Script Date: 1/1/2022 8:51:38 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[uspManageSecondaryCutover]
(
		@ListofDBs NVARCHAR(MAX) -- Enter your database name as comma separated		
)
/***********Author - Rajib Sadhu**************/
/*
EXEC dbo.uspManageSecondaryCutover 'AdventureWorks2019,TEST_1'
*/
AS
BEGIN
	SET NOCOUNT ON

		DECLARE @cmd NVARCHAR(4000)
		DECLARE @LiCounter INT = 1
		DECLARE @LiMaxCount INT
		DECLARE @LsDatabaseName SYSNAME
		DECLARE @JobName NVARCHAR(1000)

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

		/****************Check if the database specified exists***********************************/
		IF EXISTS (SELECT DatabaseName from #DBList WHERE DatabaseName NOT IN (SELECT name FROM master.sys.databases))
		BEGIN
		RAISERROR('One of more databases is not present. Cleanup operation is cancelled.', 16, 1)
		RETURN 1
		END

		/*******************************Drop Tran Log Restore Jobs***************************/
		

		IF EXISTS(SELECT 1 FROM [dbo].[tblLSTracking] WHERE	[processing_status] <> 'Processed' AND [database_name] IN (SELECT DatabaseName from #DBList))
		BEGIN
				RAISERROR('Latest Transaction Logs are not applied for one or more databases in the list. Cutover operation is aborted.', 16, 1)
				RETURN 1
		END

		SET @LiCounter = 1

		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter

						SET @JobName = 'LSRestore_' + @LsDatabaseName

						SET @cmd = 'EXEC msdb..sp_delete_job @job_name = ' + '''' +  @JobName + '''' 
						
						EXEC (@cmd)	

						SET @LiCounter = @LiCounter +1
				END
				ElSE
				BEGIN
						BREAK
				END

		END --WHILE(1=1)

		/******************************Finish Restore***********************************************/
		SET @LiCounter = 1
		
		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter

						SET @cmd = 'EXECUTE msdb.dbo.rds_finish_restore ' + '''' +  @LsDatabaseName + '''' 
						
						EXEC (@cmd)						

						SET @LiCounter = @LiCounter +1
				END
				ElSE
				BEGIN
						BREAK
				END

		END --WHILE(1=1)

	SET NOCOUNT OFF
END
GO
/****** Object:  StoredProcedure [dbo].[uspManageSecondaryLSTracking]    Script Date: 1/1/2022 8:51:38 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspManageSecondaryLSTracking]
(
		@ListofDBs NVARCHAR(MAX) -- Enter your database name as comma separated
	
)
/***********Author - Rajib Sadhu**************/
/*
EXEC dbo.uspManageSecondaryLSTracking 'AdventureWorks2019,AdventureWorksDW2019,pubs2,TEST_1'
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

	
	CREATE TABLE #TblTaskStatus
	(
			task_id	int,
			task_type varchar(250),
			[database_name] varchar(500),	
			[complete] numeric(5,2),
			[duration_mins] int,
			lifecycle varchar(250),
			task_info varchar(max),
			last_updated datetime,	
			created_at datetime,
			S3_object_arn varchar(8000),
			overwrite_S3_backup_file varchar(50),	
			KMS_master_key_arn varchar(500),
			filepath varchar(500),
			overwrite_file varchar(500)
	)


	SET @LiCounter = 1

	WHILE(1=1)
	BEGIN
			SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

			IF(@LiCounter <= @LiMaxCount)
			BEGIN
					SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter
						
					---Populate tran log restore status
					
					INSERT INTO #TblTaskStatus
					EXEC msdb.dbo.rds_task_status @LsDatabaseName

				
					UPDATE		LST
					SET			LST.processing_status = 'Processed'

					FROM		[dbo].[tblLSTracking] LST
					INNER JOIN	#TblTaskStatus TS
					ON			TS.database_name = LST.database_name
					AND			TS.task_type = 'RESTORE_DB_LOG_NORECOVERY'
					AND			LST.database_name = @LsDatabaseName
					AND			LST.backup_type = 'Log'
					AND			TS.lifecycle = 'SUCCESS'
					AND			LST.file_name = SUBSTRING(TS.S3_object_arn, CHARINDEX(TS.database_name + '_', TS.S3_object_arn), LEN(TS.S3_object_arn)) 
					AND			LST.processing_status = 'in-progress'


					DELETE FROM #TblTaskStatus
							
					SET @LiCounter = @LiCounter +1

			END
			ElSE
			BEGIN
					BREAK
			END

	END --WHILE(1=1)


	DROP TABLE #DBList
	DROP TABLE #TblTaskStatus

	SET NOCOUNT OFF
END
GO
/****** Object:  StoredProcedure [dbo].[uspManageSecondaryRestoreLogs]    Script Date: 1/1/2022 8:51:38 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspManageSecondaryRestoreLogs]
(
		@DatabaseName NVARCHAR(128) -- Enter your database name as comma separated
		,@PrimaryServerName NVARCHAR(500) -- Enter the Primary Server Name in the log shipping, can be found using SELECT SERVERPROPERTY('MachineName')		
		,@S3BucketARN NVARCHAR(500) -- Pass the S3 Bucket ARN
)
/***********Author - Rajib Sadhu**************/
/*
EXEC dbo.uspManageSecondaryRestoreLogs 'AdventureWorks2019', 'ec2amaz-g5rhpdl' , 'arn:aws:s3:::rds-sql-backup-restore-demo'
*/
AS
BEGIN
		SET NOCOUNT ON

		DECLARE @LiCounter INT = 1
		DECLARE @LiMaxCount INT
		DECLARE @cmd NVARCHAR(4000)
		DECLARE @LsFileName NVARCHAR(1000)
		DECLARE @BackupDir NVARCHAR(4000)
		
		CREATE TABLE #tblLSTracking(
			[tracking_id] [int] identity(1,1),
			[Server] [char](100) NULL,
			[database_name] [nvarchar](128) NULL,
			[backup_start_date] [datetime] NULL,
			[backup_finish_date] [datetime] NULL,
			[backup_type] [varchar](8) NULL,
			[backup_size] [numeric](20, 0) NULL,
			[physical_device_name] [nvarchar](260) NULL,
			[file_name] [nvarchar](260) NULL,
			[backupset_name] [nvarchar](128) NULL,
			[processing_status] [varchar](30) NULL
		) 

		/********************Pull all the tran log records not processed***************/

		INSERT INTO #tblLSTracking
		(
			[Server]
			,[database_name]
			,[backup_start_date]
			,[backup_finish_date]
			,[backup_type]
			,[backup_size]
			,[physical_device_name]
			,[file_name]
			,[backupset_name]
			,[processing_status]
		)
		
		SELECT [Server]
			  ,[database_name]
			  ,[backup_start_date]
			  ,[backup_finish_date]
			  ,[backup_type]
			  ,[backup_size]
			  ,[physical_device_name]
			  ,[file_name]
			  ,[backupset_name]
			  ,[processing_status]

		FROM	[dbo].[tblLSTracking]
		WHERE	[database_name] = @DatabaseName
		AND		[backup_type] = 'Log'
		AND		[processing_status] IS NULL
		ORDER BY [backup_finish_date] ASC


		/******************************Restore Tran Log Backup*******************************/
		SET @LiCounter = 1
		
		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX([tracking_id]) FROM #tblLSTracking

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsFileName = [file_name] FROM #tblLSTracking WHERE [tracking_id] = @LiCounter

						SET @BackupDir = '''' + @S3BucketARN + '/' + LOWER(@PrimaryServerName) + '/' + LOWER(@DatabaseName) + '/' + @LsFileName + ''''
			
						SET @cmd = 'exec msdb.dbo.rds_restore_log @restore_db_name=' + '''' +  @DatabaseName + '''' + ', @s3_arn_to_restore_from=' + @BackupDir + ', @with_norecovery=1;'						
							
						EXEC (@cmd)

						--print @cmd

						UPDATE [dbo].[tblLSTracking] SET [processing_status] = 'in-progress' WHERE [file_name] = @LsFileName						

						SET @LiCounter = @LiCounter +1
				END
				ElSE
				BEGIN
						BREAK
				END

		END --WHILE(1=1)


		DROP TABLE #tblLSTracking


		SET NOCOUNT OFF

END
GO
/****** Object:  StoredProcedure [dbo].[uspManageSecondarySetSecondary]    Script Date: 1/1/2022 8:51:38 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspManageSecondarySetSecondary]
(
		@ListofDBs NVARCHAR(MAX) -- Enter your database name as comma separated
		,@S3BucketARN NVARCHAR(500) -- Pass the S3 Bucket ARN
		,@PrimaryServerName NVARCHAR(500) -- Enter the Primary Server Name in the log shipping, can be found using SELECT SERVERPROPERTY('MachineName')
		,@RDSAdminUser NVARCHAR(100) -- Enter RDS Admin user name
		,@LogRestoreFrequency SMALLINT --Enter how frequently you want to restore tran logs
		
)
/***********Author - Rajib Sadhu**************/
/*
EXEC dbo.uspManageSecondarySetSecondary 'AdventureWorks2019,AdventureWorksDW2019,pubs2,TEST_1', 'arn:aws:s3:::rds-sql-backup-restore-demo', 'ec2amaz-g5rhpdl' , 'admin', 15
*/
AS
BEGIN
		SET NOCOUNT ON
		
		DECLARE @LvMachineName NVARCHAR(500)
		DECLARE @cmd NVARCHAR(4000)
		DECLARE @LiCounter INT = 1
		DECLARE @LiMaxCount INT
		DECLARE @LsDatabaseName SYSNAME
		DECLARE @jobId BINARY(16)
		DECLARE @JobName NVARCHAR(1000)
		DECLARE @BackupDir NVARCHAR(4000)
		DECLARE @Backupshare NVARCHAR(4000)
		DECLARE @LSBackUpScheduleUID   UNIQUEIDENTIFIER 
		DECLARE @LSBackUpScheduleID    INT 
		

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
    
		/***************Make sure DB List does not have any system databases***********************/
		IF EXISTS(SELECT 1 FROM #DBList WHERE DatabaseName IN ('master','model','msdb','tempdb','rdsadmin','ssisdb'))
		BEGIN
			RAISERROR('Please remove system database/s from the list to proceed.', 16, 1)
			RETURN 1
		END

		/****************Check if the database specified exists***********************************/
		IF EXISTS (SELECT DatabaseName from #DBList WHERE DatabaseName IN (SELECT name FROM master.sys.databases))
		BEGIN
		RAISERROR('One of more databases in the list already present. Restore operation is cancelled.', 16, 1)
		RETURN 1
		END

		
		/******************************Restore Full Backup*******************************/
		SET @LiCounter = 1
		
		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter

						SET @BackupDir = '''' + @S3BucketARN + '/' + LOWER(@PrimaryServerName) + '/' + LOWER(@LsDatabaseName) + '/' + @LsDatabaseName + '_fullbackup.bak' + ''''
			
						SET @cmd = 'exec msdb.dbo.rds_restore_database @restore_db_name=' + '''' +  @LsDatabaseName + '''' + ', @s3_arn_to_restore_from=' + @BackupDir + ', @type=''FULL'', @with_norecovery=1;'
						
						EXEC (@cmd)

						UPDATE [dbo].[tblLSTracking] SET [processing_status] = 'Processed' WHERE [database_name] = @LsDatabaseName AND [backup_type] = 'Database' AND [processing_status] IS NULL

						SET @LiCounter = @LiCounter +1
				END
				ElSE
				BEGIN
						BREAK
				END

		END --WHILE(1=1)

		

		/*******************************Tran Log Restore Job Creation******************************/
		
		SET @LiCounter = 1

		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter

						SET @JobName = 'LSRestore_' + @LsDatabaseName
						
						SET @cmd = 'EXEC [dbmig].[dbo].[uspManageSecondaryRestoreLogs] ' + '''' + @LsDatabaseName + '''' + ', ' + '''' + @PrimaryServerName + '''' + ', ' + '''' + @S3BucketARN + ''''

						SET @jobId = NULL
						SET @LSBackUpScheduleUID   = NULL 
						SET @LSBackUpScheduleID    = NULL 
																
						EXEC  msdb.dbo.sp_add_job @job_name=@JobName, 
								@enabled=1, 
								@notify_level_eventlog=0, 
								@notify_level_email=2, 
								@notify_level_page=2, 
								@delete_level=0, 
								@category_name=N'[Uncategorized (Local)]', 
								@owner_login_name=@RDSAdminUser, @job_id = @jobId OUTPUT

						EXEC msdb.dbo.sp_add_jobserver @job_name=@JobName, @server_name = @@SERVERNAME

						EXEC msdb.dbo.sp_add_jobstep @job_name=@JobName, @step_name=N'tran log restore', 
								@step_id=1, 
								@cmdexec_success_code=0, 
								@on_success_action=1, 
								@on_fail_action=2, 
								@retry_attempts=0, 
								@retry_interval=0, 
								@os_run_priority=0, @subsystem=N'TSQL', 
								@command=@cmd, 
								@database_name=N'master', 
								@flags=0


						EXEC msdb.dbo.sp_add_schedule 
									@schedule_name =N'LSRestoreSchedule' 
									,@enabled = 1 
									,@freq_type = 4 
									,@freq_interval = 1 
									,@freq_subday_type = 4 
									,@freq_subday_interval = @LogRestoreFrequency 
									,@freq_recurrence_factor = 0 
									,@active_start_date = 20100101 
									,@active_end_date = 99991231 
									,@active_start_time = 0 
									,@active_end_time = 235900 
									,@schedule_uid = @LSBackUpScheduleUID OUTPUT 
									,@schedule_id = @LSBackUpScheduleID OUTPUT 

							EXEC msdb.dbo.sp_attach_schedule 
									@job_id = @jobId 
									,@schedule_id = @LSBackUpScheduleID  
						

						SET @LiCounter = @LiCounter +1
				END
				ElSE
				BEGIN
						BREAK
				END

		END --WHILE(1=1)
		
		
		/*******************************Create LSTracking-Secondary  Job******************************/

		SET @JobName = 'LSTracking-Secondary'
		
		SET @cmd = 'EXEC [dbmig].[dbo].[uspManageSecondaryLSTracking] ' + '''' + CAST(@ListofDBs AS NVARCHAR(4000)) + ''''

		SET @jobId = NULL
		SET @LSBackUpScheduleUID   = NULL 
		SET @LSBackUpScheduleID    = NULL 
																
		EXEC  msdb.dbo.sp_add_job @job_name=@JobName, 
				@enabled=1, 
				@notify_level_eventlog=0, 
				@notify_level_email=0, 
				@notify_level_netsend=0, 
				@notify_level_page=0, 
				@delete_level=0, 
				@description=N'No description available.', 
				@category_name=N'[Uncategorized (Local)]',  
				@owner_login_name=@RDSAdminUser, @job_id = @jobId OUTPUT

		EXEC msdb.dbo.sp_add_jobserver @job_name=@JobName, @server_name = @@SERVERNAME

		EXEC msdb.dbo.sp_add_jobstep @job_name=@JobName, @step_name=N'Track secondary LS Restore', 
				@step_id=1, 
				@cmdexec_success_code=0, 
				@on_success_action=1, 
				@on_success_step_id=0, 
				@on_fail_action=2, 
				@on_fail_step_id=0, 
				@retry_attempts=0, 
				@retry_interval=0, 
				@os_run_priority=0, @subsystem=N'TSQL', 
				@command=@cmd, 
				@database_name=N'master', 
				@flags=0							

		EXEC msdb.dbo.sp_add_schedule 
				@schedule_name =N'run every 5 minutes' 
				,@enabled = 1 
				,@freq_type = 4 
				,@freq_interval = 1 
				,@freq_subday_type = 4 
				,@freq_subday_interval = 5				
				,@freq_relative_interval=0 
				,@freq_recurrence_factor = 0 
				,@active_start_date = 20100101 
				,@active_end_date = 99991231 
				,@active_start_time = 0 
				,@active_end_time = 235900 
				,@schedule_uid = @LSBackUpScheduleUID OUTPUT 
				,@schedule_id = @LSBackUpScheduleID OUTPUT 

		EXEC msdb.dbo.sp_attach_schedule 
				@job_id = @jobId 
				,@schedule_id = @LSBackUpScheduleID 



		DROP TABLE #DBList

		SET NOCOUNT OFF
END
GO