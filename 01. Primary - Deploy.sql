
/*********************************PLEASE READ THIS BEFORE YOU PROCEED*****************************************/
/***************DO NOT RUN THIS SCRIPT ON SECONDARY, THIS SCRIPT ONLY TO BE RUN ON PRIMARY********************/

USE [master]
GO
CREATE DATABASE [dbmig]
GO

USE [dbmig]
GO
/****** Object:  StoredProcedure [dbo].[uspManagePrimarySetLogShipping]    Script Date: 1/1/2022 6:38:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspManagePrimarySetLogShipping]
(
		@ListofDBs NVARCHAR(MAX) -- Enter your database name as comma separated
		,@S3DriveLetter CHAR(1) -- Mount S3 and pass the drive letter here		
		,@LogBackupFrequency SMALLINT --Enter how frequently you want to backup tran logs


)
/***********Author - Rajib Sadhu**************/
/*
EXEC dbo.uspManagePrimarySetLogShipping 'AdventureWorks2019,AdventureWorksDW2019,pubs2,TEST_1', 'e', 5
*/
AS
BEGIN
		SET NOCOUNT ON
		
		DECLARE @LvMachineName NVARCHAR(500)
		DECLARE @LiCounter INT = 1
		DECLARE @LiMaxCount INT
		DECLARE @LsDatabaseName SYSNAME
		DECLARE @JobName NVARCHAR(1000)
		DECLARE @BackupDir NVARCHAR(4000)
		DECLARE @Backupshare NVARCHAR(4000)
		DECLARE @LSBackupJobId UNIQUEIDENTIFIER 
		DECLARE @LSPrimaryId   UNIQUEIDENTIFIER 
		DECLARE @SPAdd_RetCode INT 
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
		IF EXISTS (SELECT DatabaseName from #DBList WHERE DatabaseName NOT IN (SELECT name FROM master.sys.databases))
		BEGIN
		RAISERROR('One of more databases in the list are not valid. Supply valid database name/s. To see available databases, use sys.databases.', 16, 1)
		RETURN 1
		END

		/*****************Check if the database is not online*************************************/

		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter
						
						IF (DATABASEPROPERTYEX(@LsDatabaseName, N'STATUS') != N'ONLINE')
						BEGIN
						RAISERROR(32008, 10, 1, @LsDatabaseName)
						END

						SET @LiCounter = @LiCounter +1
				END
				ElSE
				BEGIN
						BREAK
				END

		END --WHILE(1=1)

		/********Check if logshipping entry for this database already exists*****************/

		IF EXISTS(SELECT 1 FROM #DBList WHERE DatabaseName IN (SELECT primary_database FROM msdb.dbo.log_shipping_primary_databases))
		BEGIN
			RAISERROR('One or more databases in the list already configured in Log Shipping. Please remove database/s from the list to proceed.', 16, 1)
			RETURN 1
		END
			     

		/****************Make sure S3 is already mounted and Drive Letter is passed as input*******/

		IF(@S3DriveLetter NOT LIKE '[A-Z]')
		BEGIN
			RAISERROR('Please pass a valid drive letter.', 16, 1)
			RETURN 1
		END	


		
		/*******************************Enable Log Shipping******************************/

		SET @LiCounter = 1
		
		SELECT @LvMachineName = LOWER(CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(500)))

		IF(@LvMachineName IS NULL)
		BEGIN
				SET @LvMachineName = LOWER(CAST(SERVERPROPERTY('MachineName') AS NVARCHAR(500)))
		END

		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter

						SET @JobName = '_LSBackup_' + @LsDatabaseName
						SET @BackupDir = UPPER(@S3DriveLetter) + ':\' + @LvMachineName + '\' + LOWER(@LsDatabaseName)
						SET @Backupshare = '\\' + LOWER(@LsDatabaseName) + '\'

						SET @LSBackupJobId = NULL 
						SET @LSPrimaryId   = NULL 
						SET @SPAdd_RetCode = NULL 
						SET @LSBackUpScheduleUID   = NULL 
						SET @LSBackUpScheduleID    = NULL 

						EXEC @SPAdd_RetCode = master.dbo.sp_add_log_shipping_primary_database 
								@database = @LsDatabaseName
								,@backup_directory = @BackupDir
								,@backup_share = @Backupshare 
								,@backup_job_name = @JobName
								,@backup_retention_period = 1440
								,@backup_threshold = 180 
								,@threshold_alert_enabled = 1
								,@history_retention_period = 5760 
								,@backup_job_id = @LSBackupJobId OUTPUT 
								,@primary_id = @LSPrimaryId OUTPUT 
								,@overwrite = 1 


						IF (@@ERROR = 0 AND @SPAdd_RetCode = 0) 
						BEGIN 

							EXEC msdb.dbo.sp_add_schedule 
									@schedule_name =N'LSBackupSchedule' 
									,@enabled = 1 
									,@freq_type = 4 
									,@freq_interval = 1 
									,@freq_subday_type = 4 
									,@freq_subday_interval = @LogBackupFrequency
									,@freq_recurrence_factor = 0 
									,@active_start_date = 20100101 
									,@active_end_date = 99991231 
									,@active_start_time = 0 
									,@active_end_time = 235900 
									,@schedule_uid = @LSBackUpScheduleUID OUTPUT 
									,@schedule_id = @LSBackUpScheduleID OUTPUT 

							EXEC msdb.dbo.sp_attach_schedule 
									@job_id = @LSBackupJobId 
									,@schedule_id = @LSBackUpScheduleID  

							EXEC msdb.dbo.sp_update_job 
									@job_id = @LSBackupJobId 
									,@enabled = 1


						END 

						EXEC master.dbo.sp_add_log_shipping_alert_job 					

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
GO
/****** Object:  StoredProcedure [dbo].[uspManagePrimarySetPrimary]    Script Date: 1/1/2022 6:38:31 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspManagePrimarySetPrimary]
(
		@ListofDBs NVARCHAR(MAX) -- Enter your database name as comma separated
		,@S3DriveLetter CHAR(1) -- Mount S3 and pass the drive letter here
		,@RDSServerName NVARCHAR(500) -- Enter the endpoint for the RDS SQL Server
		,@RDSAdminUser NVARCHAR(100) -- Enter RDS Admin user name
		,@RDSAdminPassword NVARCHAR(100) -- Enter RDS Admin user password
		
)
/***********Author - Rajib Sadhu**************/
/*
EXEC dbo.uspManagePrimarySetPrimary 'AdventureWorks2019,AdventureWorksDW2019,pubs2,TEST_1', 'e', 'mssql-ad-demo.cfehwllkcxuv.us-east-1.rds.amazonaws.com','Admin','*********'
*/
AS
BEGIN
		SET NOCOUNT ON

		DECLARE @LbXPcmdShellOriginalValue BIT
		DECLARE @LvMachineName NVARCHAR(500)
		DECLARE @cmd NVARCHAR(4000)
		DECLARE @LiCounter INT = 1
		DECLARE @LiMaxCount INT
		DECLARE @LsDatabaseName SYSNAME
		DECLARE @jobId BINARY(16)
		DECLARE @JobName NVARCHAR(1000)
		DECLARE @BackupPath NVARCHAR(4000)
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
		IF EXISTS (SELECT DatabaseName from #DBList WHERE DatabaseName NOT IN (SELECT name FROM master.sys.databases))
		BEGIN
		RAISERROR('One of more databases in the list are not valid. Supply valid database name/s. To see available databases, use sys.databases.', 16, 1)
		RETURN 1
		END

		/*****************Check if the database is not online*************************************/

		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter
						
						IF (DATABASEPROPERTYEX(@LsDatabaseName, N'STATUS') != N'ONLINE')
						BEGIN
						RAISERROR(32008, 10, 1, @LsDatabaseName)
						END

						SET @LiCounter = @LiCounter +1
				END
				ElSE
				BEGIN
						BREAK
				END

		END --WHILE(1=1)

		/********Check if logshipping entry for this database already exists*****************/

		IF EXISTS(SELECT 1 FROM #DBList WHERE DatabaseName IN (SELECT primary_database FROM msdb.dbo.log_shipping_primary_databases))
		BEGIN
			RAISERROR('One or more databases in the list already configured in Log Shipping. Please remove database/s from the list to proceed.', 16, 1)
			RETURN 1
		END
			     

		/****************Make sure S3 is already mounted and Drive Letter is passed as input*******/

		IF(@S3DriveLetter NOT LIKE '[A-Z]')
		BEGIN
			RAISERROR('Please pass a valid drive letter.', 16, 1)
			RETURN 1
		END	


		/*****************Enable xp_cmdshell for this setup only***************************************/

		SELECT @LbXPcmdShellOriginalValue = CAST(value AS BIT) FROM sys.configurations WHERE name = 'xp_cmdshell'

		IF(@LbXPcmdShellOriginalValue = 0)
		BEGIN
				EXEC sp_configure 'show advanced options', 1
				RECONFIGURE

				EXEC sp_configure 'xp_cmdshell', 1
				RECONFIGURE
				
		END


		/****************Change database recovery model to Full****************************************/

		SET @LiCounter = 1

		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter
						
						IF (DATABASEPROPERTYEX(@LsDatabaseName, N'Recovery') != N'FULL')
						BEGIN
								SET @cmd = 'ALTER DATABASE ' + @LsDatabaseName + ' SET RECOVERY FULL'
								EXEC (@cmd)
						END

						SET @LiCounter = @LiCounter +1
				END
				ElSE
				BEGIN
						BREAK
				END

		END --WHILE(1=1)

		/******************Create directory and sub-directory in S3*****************************/

		SELECT @LvMachineName = LOWER(CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(500)))

		IF(@LvMachineName IS NULL)
		BEGIN
				SET @LvMachineName = LOWER(CAST(SERVERPROPERTY('MachineName') AS NVARCHAR(500)))
		END

		SET @cmd = 'mkdir ' + UPPER(@S3DriveLetter) + ':\' + @LvMachineName
		
		EXEC master..xp_cmdshell @cmd, NO_OUTPUT

		
		SET @LiCounter = 1

		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter
						
						SET @cmd = 'mkdir ' + UPPER(@S3DriveLetter) + ':\' + @LvMachineName + '\' + LOWER(@LsDatabaseName)						

						--print @cmd
		
						EXEC master..xp_cmdshell @cmd, NO_OUTPUT

						SET @LiCounter = @LiCounter +1
				END
				ElSE
				BEGIN
						BREAK
				END

		END --WHILE(1=1)


		SET @LiCounter = 1

		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter
						
						SET @cmd = 'mkdir ' + UPPER(@S3DriveLetter) + ':\' + @LvMachineName + '\' + LOWER(@LsDatabaseName) + '-archive'

						EXEC master..xp_cmdshell @cmd, NO_OUTPUT

						SET @LiCounter = @LiCounter +1
				END
				ElSE
				BEGIN
						BREAK
				END

		END --WHILE(1=1)


		/**************************Create Linked Server between Primary and Secondary****************/

		IF NOT EXISTS(SELECT 1 FROM sys.servers WHERE name = 'RDSDBServer' AND is_linked = 1)
		BEGIN

			EXEC master.dbo.sp_addlinkedserver @server = N'RDSDBServer', @srvproduct=N'', @provider=N'SQLNCLI', @datasrc=@RDSServerName;

			EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'RDSDBServer',@useself=N'False',@locallogin=NULL,@rmtuser=@RDSAdminUser,@rmtpassword=@RDSAdminPassword;

			
		END

		/*******************************Create Full Backup Jobs******************************/

		SET @LiCounter = 1

		WHILE(1=1)
		BEGIN
				SELECT @LiMaxCount = MAX(DatabaseId) FROM #DBList

				IF(@LiCounter <= @LiMaxCount)
				BEGIN
						SELECT @LsDatabaseName = DatabaseName FROM #DBList WHERE DatabaseId = @LiCounter

						SET @JobName = '_FullBackup_' + @LsDatabaseName
						SET @BackupPath = UPPER(@S3DriveLetter) + ':\' + @LvMachineName + '\' + LOWER(@LsDatabaseName)

						SET @cmd = 'BACKUP DATABASE [' + @LsDatabaseName + '] TO  DISK = N''' + @BackupPath + '\' + @LsDatabaseName + '_fullbackup.bak''' + ' WITH NOFORMAT, NOINIT,  NAME = N''' + @LsDatabaseName + '-Full Database Backup''' + ', SKIP, NOREWIND, NOUNLOAD,  STATS = 10'

						SET @jobId = NULL
																
						EXEC  msdb.dbo.sp_add_job @job_name=@JobName, 
								@enabled=1, 
								@notify_level_eventlog=0, 
								@notify_level_email=2, 
								@notify_level_page=2, 
								@delete_level=0, 
								@category_name=N'[Uncategorized (Local)]', 
								@owner_login_name=N'sa', @job_id = @jobId OUTPUT

						EXEC msdb.dbo.sp_add_jobserver @job_name=@JobName, @server_name = @@SERVERNAME

						EXEC msdb.dbo.sp_add_jobstep @job_name=@JobName, @step_name=N'full backup', 
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
						

						SET @LiCounter = @LiCounter +1
				END
				ElSE
				BEGIN
						BREAK
				END

		END --WHILE(1=1)


		/*******************************Create LS Tracking Job******************************/

		SET @JobName = '_LSTracking'
		
		SET @cmd = 'EXEC [dbmig].[dbo].[uspManagePrimaryLSTracking] ' + '''' + CAST(@ListofDBs AS NVARCHAR(4000)) + ''''

		SET @jobId = NULL
		SET @LSBackUpScheduleUID   = NULL 
		SET @LSBackUpScheduleID    = NULL 
																
		EXEC  msdb.dbo.sp_add_job @job_name=@JobName, 
				@enabled=0, 
				@notify_level_eventlog=0, 
				@notify_level_email=2, 
				@notify_level_page=2, 
				@delete_level=0, 
				@category_name=N'[Uncategorized (Local)]', 
				@owner_login_name=N'sa', @job_id = @jobId OUTPUT

		EXEC msdb.dbo.sp_add_jobserver @job_name=@JobName, @server_name = @@SERVERNAME

		EXEC msdb.dbo.sp_add_jobstep @job_name=@JobName, @step_name=N'LS Tracking', 
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
				@schedule_name =N'LSTrackingSchedule' 
				,@enabled = 1 
				,@freq_type = 4 
				,@freq_interval = 1 
				,@freq_subday_type = 4 
				,@freq_subday_interval = 5 
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

		/********************Set the xp_cmdshell value to its original****************/

		IF(@LbXPcmdShellOriginalValue = 0)
		BEGIN
				EXEC sp_configure 'xp_cmdshell', 0
				RECONFIGURE
				
		END

		DROP TABLE #DBList

		SET NOCOUNT OFF
END
GO