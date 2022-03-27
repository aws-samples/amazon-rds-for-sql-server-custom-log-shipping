## Automate on-premises or Amazon EC2 SQL Server to Amazon RDS for SQL Server migration using custom log shipping

## Architecture overview
The custom log shipping solution is built using Microsoft’s native log shipping principles, where the transaction log backups are copied from the primary SQL Server instance to the secondary SQL Server instance and applied to each of the secondary databases individually on a scheduled basis. A tracking table records the history of backup and restore operations, and is used as the monitor. The following diagram illustrates this architecture.

![image](https://user-images.githubusercontent.com/96596850/160265303-45180db9-474b-4ef9-b628-1051c52c8154.png)



TODO: Fill this README out!

Be sure to:

* Change the title in this README
* Edit your repository description on GitHub

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.

