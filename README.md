## Automate on-premises or Amazon EC2 SQL Server to Amazon RDS for SQL Server migration using custom log shipping

## Architecture overview
The custom log shipping solution is built using Microsoft’s native log shipping principles, where the transaction log backups are copied from the primary SQL Server instance to the secondary SQL Server instance and applied to each of the secondary databases individually on a scheduled basis. A tracking table records the history of backup and restore operations, and is used as the monitor. The following diagram illustrates this architecture.

![image](https://user-images.githubusercontent.com/96596850/160265303-45180db9-474b-4ef9-b628-1051c52c8154.png)

## Prerequisites
To test this solution, you must have the following prerequisites:

* An AWS account
* An S3 bucket
*	An RDS for SQL Server instance created in Single-AZ mode
*	The native backup and restore option enabled on the RDS for SQL Server instance using the S3 bucket
*	An EC2 instance with SQL Server installed and a user database configured
*	An Amazon S3 file gateway created using Amazon EC2 as Platform options
*	A file share created using Server Message Block (SMB) for Access objects using input and authentication method for Guest access
*	On the primary SQL Server instance, the following command is run at the command prompt to store the guest credential in Windows Credential Manager:

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




TODO: Fill this README out!

Be sure to:

* Change the title in this README
* Edit your repository description on GitHub

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

