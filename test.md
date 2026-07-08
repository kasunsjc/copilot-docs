“The log for database '' is not available.  Check the operating system error log for related error messages. Resolve any errors and restart the database.
“The service has encountered an error processing your request. Please try again. Error code 9001.”



Your database  in  experienced failover due to planned maintenance. To ensure high quality of the service and safe execution environment, we roll out the upgrades on a monthly schedule. Typically, upgrade payload includes OS patches and security fixes, new SQL product features and repairs as well as most recent 3rd party bits. Planned failovers are almost always instantaneous and last at most a few seconds. We sincerely apologize for the inconvenience this has caused to you and your business.
 
It appears that the reconfigurations for deployments occurred on the 3rd 4th and 5th, can occur in busy regions where placement does not always land on an upgraded node.
 
With specific regard to the 9001 errors 
 
Error: 9001 – The log for database '%database_name%' is not available
This error indicates that the transaction log for the specified database cannot be accessed. The transaction log is critical for maintaining database integrity and supporting recovery operations. When this log becomes unavailable, the database cannot function properly.
 
Root Cause
 
The error occurs at the end of database reconfiguration events when the transaction log is taken 'off-line' to prevent updates to the database before the new node is brought on-line.
 
Reconfiguration events are normal, expected, and transient, typically they will last a few seconds, but depending on workload at the time of the reconfiguration this time may be extended.
 
Reconfigurations happen for several reasons:
 
•	Database Scale operations.
•	Changes to the Maintenance window configured for the database.
•	Load balancing across servers to optimize performance.
•	Planned deployments or updates in the region where your server or databases reside.
•	Health recovery actions triggered by hardware or software issues.
 
 
Impact
 
During reconfiguration, active connections may be interrupted.
The database may temporarily become inaccessible, causing applications to fail if they do not handle transient errors correctly.
 
Recommended Actions
 
Implement Retry Logic
 
Because reconfigurations are transient (usually lasting only a few seconds), applications should include retry logic to handle temporary connectivity failures gracefully.
Use exponential backoff strategies to avoid overwhelming the system during retries.
 
 
Additional Guidance
 
https://learn.microsoft.com/en-us/azure/azure-sql/database/troubleshoot-common-connectivity-issues?…
 
