## Automate on-premises or Amazon EC2 SQL Server to Amazon RDS for SQL Server migration using custom log shipping

## Architecture overview
The custom log shipping solution is built using Microsoft’s native log shipping principles, where the transaction log backups are copied from the primary SQL Server instance to the secondary SQL Server instance and applied to each of the secondary databases individually on a scheduled basis. A tracking table records the history of backup and restore operations, and is used as the monitor. The following diagram illustrates this architecture.

In our solution, we reference the on-premises source SQL Server as the primary SQL Server instance and the target Amazon RDS for SQL Server as the secondary SQL Server instance.

![image](https://user-images.githubusercontent.com/96596850/160265303-45180db9-474b-4ef9-b628-1051c52c8154.png)

## Prerequisites
To test this solution, you must have the following prerequisites:

* An AWS account
* An S3 bucket
* An RDS for SQL Server instance created in Single-AZ mode
* The native backup and restore option enabled on the RDS for SQL Server instance using the S3 bucket
* An on-prem SQL Server instance with user databases
* An Amazon S3 file gateway [created](https://docs.aws.amazon.com/filegateway/latest/files3/create-gateway-file.html)
* A file share [created](https://docs.aws.amazon.com/filegateway/latest/files3/CreatingAnSMBFileShare.html) using Server Message Block (SMB) for Access objects using input and authentication method for Guest access
* On the primary SQL Server instance, the following command is run at the command prompt to store the guest credential in Windows Credential Manager:

cmdkey /add:GatewayIPAddress /user:DomainName\smbguest /pass:Password

For example, 

```

C:\Users\Administrator>cmdkey /add:172.31.43.62\rds-sql-backup-restore-demo /user:sgw-61DA3908\smbguest /pass:***********.

```

*	The S3 bucket/SMB file share is mounted at the primary SQL Server using the following command:

net use WindowsDriveLetter: \\$GatewayIPAddress\$Path /persistent:yes /savecred

For example, 

```

C:\Users\Administrator>net use E: \\172.31.43.62\rds-sql-backup-restore-demo /persistent:yes /savecred.

```

*	Follow the optional steps mentioned later in this post if the newly mounted volume is not visible to the primary SQL Server instance
*	sysadmin permission on the primary SQL Server instance and access to the primary user name and password for the secondary SQL Server instance

## Stage the solution
To stage this solution, complete the following steps:

1.	Navigate to the GitHub repo and download the source code from your web browser.
2.	Download the `amazon-rds-for-sql-server-custom-log-shipping-main.zip` folder on your workspace.
3.	Open SQL Server Management Studio (SSMS) and connect to the primary SQL Server instance.
4.	Locate the `01. Primary - Deploy.sql` file within the amazon-rds-for-sql-server-custom-log-shipping-main folder and open in a new window.
5.	Run the code against the primary SQL Server instance to create a new database called dbmig with stored procedures in it.
6.	Locate the `02. Secondary - Deploy.sql` file within the amazon-rds-for-sql-server-custom-log-shipping-main folder and open in a new window.
7.	Run the code against the secondary SQL Server instance to create a new database called dbmig with a table and stored procedures in it.

## Implement the solution
To implement the custom log shipping solution, complete the following steps:

1.	Open SSMS and connect to the primary SQL Server instance.
2.	Open a new query window and run the following command after replacing the input parameter values.

```TSQL

USE [dbmig]
GO

DECLARE @RC int
DECLARE @ListofDBs nvarchar(max)
DECLARE @S3DriveLetter char(1)
DECLARE @RDSServerName nvarchar(500)
DECLARE @RDSAdminUser nvarchar(100)
DECLARE @RDSAdminPassword nvarchar(100)

EXECUTE @RC = [dbo].[uspManagePrimarySetPrimary] 
   @ListofDBs = '<database_1,database_2,database_3>'
  ,@S3DriveLetter = '<s3_driver_letter>'
  ,@RDSServerName = '<rds_sql_instancename,port>'
  ,@RDSAdminUser = '<admin_user_name>'
  ,@RDSAdminPassword = '<admin_user_password>'
GO

```

3.	Disable any existing transaction log backup job you might have as part of your database maintenance plan.
4.	Locate the 03. Primary - Deploy LS Tracking.sql file within the amazon-rds-for-sql-server-custom-log-shipping-main folder and open in a new window.
5.	Run the code against the primary SQL Server instance to create a new procedure uspManagePrimaryLSTracking within the dbmig database.
6.	_FullBackup_ jobs are not scheduled as default. You may run them one at a time or you can run them all together by navigating to Job Activity Monitor in SQL Server Agent. 
7.	Wait for the full backup to complete and then enable the _LSTracking job, which is deployed as disabled. The tracking job is scheduled to run every 5 minutes.
8.	Open a new query window and run the following command at the primary SQL Server instance after replacing the input parameter values. 

```TSQL

USE [dbmig]
GO

DECLARE @RC int
DECLARE @ListofDBs nvarchar(max)
DECLARE @S3DriveLetter char(1)
DECLARE @LogBackupFrequency smallint

EXECUTE @RC = [dbo].[uspManagePrimarySetLogShipping] 
   @ListofDBs = '<database_1,database_2,database_3>'
  ,@S3DriveLetter = '<s3_driver_letter>'
  ,@LogBackupFrequency = '<log_backup_frequency_in_minutes>'
GO

```

9.	Open a new query window and run the following command at the primary SQL Server instance to capture the primary SQL Server instance name, which we use later: 

```TSQL

DECLARE @LvSQLInstanceName VARCHAR(500)
SELECT @LvSQLInstanceName = CONVERT(VARCHAR(500), SERVERPROPERTY('InstanceName'))
IF(@LvSQLInstanceName IS NULL)
BEGIN
SET @LvSQLInstanceName = CONVERT(VARCHAR(500), SERVERPROPERTY('MachineName'))
END
SELECT @LvSQLInstanceName

```
10.	Open SSMS and connect to the secondary SQL Server instance.
11.	Open a new query window and run the following command after replacing the input parameter values. 

```TSQL

USE [dbmig]
GO

DECLARE @RC int
DECLARE @ListofDBs nvarchar(max)
DECLARE @S3BucketARN nvarchar(500)
DECLARE @PrimaryServerName nvarchar(500)
DECLARE @RDSAdminUser nvarchar(100)
DECLARE @LogRestoreFrequency smallint

EXECUTE @RC = [dbo].[uspManageSecondarySetSecondary] 
   @ListofDBs = '<database_1,database_2,database_3>'
  ,@S3BucketARN = '<s3_bucket_arn>'
  ,@PrimaryServerName = 'primary_sql_instance_name'
  ,@RDSAdminUser = '<admin_user_name>'
  ,@LogRestoreFrequency = '<log_restore_frequency_in_minutes>'
GO
```

12.	Consider updating your operational run-book to refer to the mount point (E:\ drive) as your new transaction log backup location for any point-in-time recovery scenario until the cutover.





## Troubleshooting

If for any reason you find the secondary SQL Server instance is working on a specific transaction log file for longer than expected and you want to reset it, complete the following steps:

1.	Open SSMS and connect to the secondary SQL Server instance.
2.	Open a new query window and run the following command after replacing the database name and file name in the input parameter. For example:

```TSQL

UPDATE [dbmig].[dbo].[tblLSTracking]
SET	[processing_status] = NULL	
WHERE [database_name] = 'AdventureWorks2019'
AND [file_name] = 'AdventureWorks2019_20220213184501.trn'
AND [processing_status] = 'in-progress'

```


## Clean up

1.	Open SSMS and connect to the primary SQL Server instance.
2.	Remove the log shipping configuration for each database:

```TSQL

EXECUTE sp_delete_log_shipping_primary_database @database_name

```

3.	Delete _FullBackup_ jobs:

```TSQL

EXEC msdb..sp_delete_job @job_name = <enter_job_name>

```

4.	Delete the _LSTracking job:

```TSQL

EXEC msdb..sp_delete_job @job_name = <enter_job_name>

```

5.	Open SSMS and connect to the secondary SQL Server instance.
6.	Delete the LSTracking and LSRestore_ jobs:

```TSQL

EXEC msdb..sp_delete_job @job_name

```

7.	If your secondary SQL Server instance isn’t in the production role and the target database is not in use, drop the log shipped databases:

```TSQL

EXECUTE msdb.dbo.rds_drop_database @database_name

```

## Limitations

*	**TDE-enabled database** – Amazon RDS for SQL Server supports Transparent Database Encryption (TDE), but as part of the managed service offering, the certificate is managed by AWS. For this reason, a TDE-enabled on-premises database backup can’t be restored on Amazon RDS for SQL Server. You need to remove TDE from the primary SQL Server instance before setting up custom log shipping. Post cutover, you can enable TDE on the secondary SQL Server instance.
*	**100 databases or less** – Amazon RDS for SQL Server supports 100 databases or less per instance as of this writing. If you have more than 100 databases at the primary, you can set up custom log shipping for the first 100 databases only.
*	**Multi-AZ setup during custom log shipping** – You can only configure Multi-AZ post cutover because Amazon RDS for SQL Server does not support full restores with NORECOVERY on Multi-AZ instances.
*	**Host OS** – The custom log shipping solution supports Microsoft Windows Server only as the host operating system for the primary SQL Server instance.
*	**Native log shipping** – If the primary SQL Server instance is configured in Microsoft native log shipping for disaster recovery (DR) or analytics, the setup needs to be removed to deploy custom log shipping.
*	**Local disk dependency** – Custom log shipping can’t be deployed if the primary SQL Server instance is backing up transaction logs to a local disk and can’t be changed to Amazon S3 (for various reasons).
*	**Express Edition** – Custom log shipping can’t be deployed if the primary or secondary SQL Server instance is Express Edition due to the SQL Agent dependency.


## License

This library is licensed under the MIT-0 License. See the LICENSE file.

