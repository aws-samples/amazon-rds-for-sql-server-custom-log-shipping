
/*********************************PLEASE READ THIS BEFORE YOU PROCEED*****************************************/
/***************DO NOT RUN THIS SCRIPT ON SECONDARY, THIS SCRIPT ONLY TO BE RUN ON PRIMARY********************/

USE [master]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[uspPersistNetworkBackupDrive]
WITH ENCRYPTION
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @LbXPcmdShellOriginalValue BIT

	/*****************Enable xp_cmdshell as onetime task if not enabled***************************************/

	SELECT @LbXPcmdShellOriginalValue = CAST(value AS BIT) FROM sys.configurations WHERE name = 'xp_cmdshell'

	IF(@LbXPcmdShellOriginalValue = 0)
	BEGIN
			EXEC sp_configure 'show advanced options', 1
			RECONFIGURE

			EXEC sp_configure 'xp_cmdshell', 1
			RECONFIGURE
				
	END
	
	/*********Replace the IP address, Drive Letter and Storage Gateway details before you create it***************/

	EXEC xp_cmdshell 'net use E: \\172.31.43.62\rds-sql-backup-restore-demo <type_password_here> /user:sgw-61DA3908\smbguest /persistent:yes /y'

	/********************Set the xp_cmdshell value to its original****************/

	IF(@LbXPcmdShellOriginalValue = 0)
	BEGIN
			EXEC sp_configure 'xp_cmdshell', 0
			RECONFIGURE
				
	END

	SET NOCOUNT OFF
END
