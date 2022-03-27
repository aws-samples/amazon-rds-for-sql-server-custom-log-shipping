## Automate on-premises or Amazon EC2 SQL Server to Amazon RDS for SQL Server migration using custom log shipping

## Architecture overview
The custom log shipping solution is built using Microsoft’s native log shipping principles, where the transaction log backups are copied from the primary SQL Server instance to the secondary SQL Server instance and applied to each of the secondary databases individually on a scheduled basis. A tracking table records the history of backup and restore operations, and is used as the monitor. The following diagram illustrates this architecture.

![image](https://user-images.githubusercontent.com/96596850/160265303-45180db9-474b-4ef9-b628-1051c52c8154.png)



TODO: Fill this README out!

Be sure to:

* Change the title in this README
* Edit your repository description on GitHub

## Limitations

•	TDE-enabled database – Amazon RDS for SQL Server supports Transparent Database Encryption (TDE), but as part of the managed service offering, the certificate is managed by AWS. For this reason, a TDE-enabled on-premises database backup can’t be restored on Amazon RDS for SQL Server. You need to remove TDE from the primary SQL Server instance before setting up custom log shipping. Post cutover, you can enable TDE on the secondary SQL Server instance.
•	100 databases or less – Amazon RDS for SQL Server supports 100 databases or less per instance as of this writing. If you have more than 100 databases at the primary, you can set up custom log shipping for the first 100 databases only.
•	Multi-AZ setup during custom log shipping – You can only configure Multi-AZ post cutover because Amazon RDS for SQL Server does not support full restores with NORECOVERY on Multi-AZ instances.
•	Host OS – The custom log shipping solution supports Microsoft Windows Server only as the host operating system for the primary SQL Server instance.
•	Native log shipping – If the primary SQL Server instance is configured in Microsoft native log shipping for disaster recovery (DR) or analytics, the setup needs to be removed to deploy custom log shipping.
•	Local disk dependency – Custom log shipping can’t be deployed if the primary SQL Server instance is backing up transaction logs to a local disk and can’t be changed to Amazon S3 (for various reasons).
•	Express Edition – Custom log shipping can’t be deployed if the primary or secondary SQL Server instance is Express Edition due to the SQL Agent dependency.


## License

This library is licensed under the MIT-0 License. See the LICENSE file.

