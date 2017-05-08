workflow AutoExportWithCheckpoint
{
    # The database and server pairs that will be exported.

    $databaseServerPairs =
    @(
        [pscustomobject]@{serverName="SAMPLESERVER1";databaseName="SAMPLEDATABASE1"},
        [pscustomobject]@{serverName="SAMPLESERVER1";databaseName="SAMPLEDATABASE2"},
        [pscustomobject]@{serverName="SAMPLESERVER2";databaseName="SAMPLEDATABASE3"}
    );

    # The number of databases you want to have running at the same time.
    $batchingLimit = 10;

    # Authenticates this RunBook with the subscription it's running on. Pass in the $automationConnection and $automationCertificate so we can $null them out later for checkpointing.
    function AutomationAuthentication
    {
        # Connection Asset Name for Authenticating (Keep as AzureClassicRunAsConnection if you created the default RunAs accounts)
        $connectionAssetName = "AzureClassicRunAsConnection";
        # Authenticate to Azure with certificate
        Write-Verbose "Get connection asset: $connectionAssetName" -Verbose;
        $automationConnection = Get-AutomationConnection -Name $connectionAssetName;
        $automationConnection
        if ($automationConnection -eq $null)
        {
            throw "Could not retrieve connection asset: $connectionAssetName. Assure that this asset exists in the Automation account.";
        }

        $certificateAssetName = $automationConnection.CertificateAssetName;
        Write-Verbose "Getting the certificate: $certificateAssetName" -Verbose;
        $automationCertificate = Get-AutomationCertificate -Name $certificateAssetName;
        if ($automationCertificate -eq $null)
        {
            throw "Could not retrieve certificate asset: $certificateAssetName. Assure that this asset exists in the Automation account.";
        }

        Write-Verbose "Authenticating to Azure with certificate." -Verbose;
        Set-AzureSubscription -SubscriptionName $automationConnection.SubscriptionName -SubscriptionId $automationConnection.SubscriptionID -Certificate $automationCertificate;
        Select-AzureSubscription -SubscriptionId $automationConnection.SubscriptionID;
    }

    # Starts the copy of $dbToCopy.
    function CopyDatabase($dbToCopy, $constants)
    {       
        # Start the copy of the database.
        Start-AzureSqlDatabaseCopy -ServerName $dbToCopy.ServerName -DatabaseName $dbToCopy.DatabaseName -PartnerDatabase $dbToCopy.DatabaseCopyName;
        # $? is true if the last command succeeded and false if the last command failed. If it is false, go to the ToDrop state.
        if(-not $? -and $constants.RetryLimit -ile $dbToCopy.RetryCount)
        {
            Write-Verbose ("Error occurred while starting copy of $($dbToCopy.DatabaseName). It will not be copied. Deleting the database copy named $($dbToCopy.DatabaseCopyName).") -Verbose
            # Set state to ToDrop in case something does get copied.
            $dbsCopying[$i].DatabaseState = $constants.ToDrop;
            # return so we don't execute the rest of the function.
            return;
        }
        elseif(-not $?)
        {
            # We failed but we haven't hit the retry limit yet so increment RetryCount and return so we try again.
            Write-Verbose ("Retrying with database $($dbToCopy.DatabaseName)") -Verbose
            $dbToCopy.RetryCount++;
            return;
        }
        # Set the state of the database object to Copying.
        $dbToCopy.DatabaseState = $constants.Copying;
        Write-Verbose ("Copying $($dbToCopy.DatabaseName) to $($dbToCopy.DatabaseCopyName)") -Verbose
        $dbToCopy.OperationStartTime = Get-Date;
    }

    # Checks on the copy of $dbCopying.
    function CheckCopy($dbCopying, $constants)
    {       
        # Get the status of the database copy.
        $check = Get-AzureSqlDatabaseCopy -ServerName $dbCopying.ServerName -DatabaseName $dbCopying.DatabaseName -PartnerDatabase $dbCopying.DatabaseCopyName;
        $currentTime = Get-Date;
        # $? is true if the last command succeeded and false if the last command failed. If it is false, go to the ToDrop state.
        if((-not $? -and $constants.RetryLimit -ile $dbCopying.RetryCount) -or ($currentTime - $dbCopying.OperationStartTime).TotalMinutes -gt $constants.WaitInMinutes)
        {
            Write-Verbose ("Error occurred during copy of $($dbCopying.DatabaseName). It will not be exported. Deleting the database copy named $($dbCopying.DatabaseCopyName).") -Verbose
            # Set state to ToDrop in case something did get copied.
            $dbCopying.DatabaseState = $constants.ToDrop;
            # return so we don't execute the rest of the function.
            return;
        }
        elseif(-not $?)
        {
            # We failed but we haven't hit the retry limit yet so increment RetryCount and return so we try again.
            Write-Verbose ("Retrying with database $($dbCopying.DatabaseName)") -Verbose
            $dbCopying.RetryCount++;
            return;
        }
        # Get the percent complete from the status to check if the database copy is done.
        $percent = $check.PercentComplete
        # $i will be $null when the copy is complete.
        if($percent -eq $null)
        {
            # The copy is complete so set the state to ToExport.
            $dbCopying.DatabaseState = $constants.ToExport;
            $dbCopying.RetryCount = 0;
        }
    }

    # Starts the export of $dbToExport and gets the credentials using $credentialName.
    function ExportDatabase($dbToExport, $credentialName, $constants)
    {       
        # Get the current time to use as a unique identifier for the blob name.
        $currentTime = Get-Date -format "_yyyy-MM-dd_HH:mm.ss";
        $blobName = $dbToExport.DatabaseName + "_ExportBlob" + $currentTime;

        $storageKeyVariableName = "STORAGEKEYVARIABLENAME";
        $storageAccountName = "STORAGEACCOUNTNAME";
        $storageContainerName = "STORAGECONTAINERNAME";

        # Set up a SQL connection context to use when exporting.
        $serverCredential = Get-AutomationPSCredential -Name $credentialName;
        $ctx = New-AzureSqlDatabaseServerContext -ServerName $dbToExport.ServerName -Credential $serverCredential;

        # Get the storage key to setup the storage context.
        $storageKey = Get-AutomationVariable -Name $storageKeyVariableName;
        # Get the storage context.
        $stgctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey;
        # Start the export. If there is an error, stop the export and set the state to ToDrop.
        $dbToExport.Export = Start-AzureSqlDatabaseExport -SqlConnectionContext $ctx -StorageContext $stgctx -StorageContainerName $storageContainerName -DatabaseName $dbToExport.DatabaseCopyName -BlobName $blobName;
        # $? is true if the last command succeeded and false if the last command failed. If it is false, go to the ToDrop state.
        if (-not $? -and $constants.RetryLimit -ile $dbToExport.RetryCount)
        {
            Write-Verbose ("Error occurred while starting export of $($dbToExport.DatabaseName). It will not be exported. Deleting the database copy named $($dbToExport.DatabaseCopyName).") -Verbose
            # Set state to ToDrop so that we drop the copied database since there was an error exporting it.
            $dbToExport.DatabaseState = $constants.ToDrop;
            # return so we don't execute the rest of the function.
            return
        }
        elseif(-not $?)
        {
            # We failed but we haven't hit the retry limit yet so increment RetryCount and return so we try again.
            Write-Verbose ("Retrying with database $($dbToExport.DatabaseName)") -Verbose
            $dbToExport.RetryCount++;
            return;
        }
        # Set the state to Exporting.
        $dbToExport.DatabaseState = $constants.Exporting;
        Write-Verbose ("Exporting $($dbToExport.DatabaseCopyName) with RequestID: $($dbToExport.Export.RequestGuid)") -Verbose
        $dbToExport.OperationStartTime = Get-Date;
    }

    # Checks on the export of $dbExporting and gets the credentials using $credentialName.
    function CheckExport($dbExporting, $credentialName, $constants)
    {       
        $serverCredential = Get-AutomationPSCredential -Name $credentialName;
        $check = Get-AzureSqlDatabaseImportExportStatus -RequestId $dbExporting.Export.RequestGuid -UserName $serverCredential.UserName -Password $serverCredential.GetNetworkCredential().Password -Server $dbExporting.ServerName

        $currentTime = Get-Date;
        # The export is complete when Status is "Completed". Wait for that to happen.
        if($check.Status -eq "Completed")
        {
            # The export id one, set the state to ToDrop because it was successful.
            $dbExporting.DatabaseState = $constants.ToDrop;
            $dbExporting.RetryCount = 0;
        }
        elseif($check.Status -eq "Failed" -and $dbExporting.RetryCount -lt $constants.RetryLimit)
        {
            # If the status is "Failed" and we have more retries left, try to export the database copy again.
            Write-Verbose ("The last export failed on database $($dbExporting.DatabaseName), going back to ToExport state to try again") -Verbose
            Write-Verbose ("$($check.ErrorMessage)") -Verbose
            $dbExporting.DatabaseState = $constants.ToExport;
            $dbExporting.RetryCount++;
            return;
        }
        elseif($constants.RetryLimit -ile $dbExporting.RetryCount -or ($currentTime - $dbExporting.OperationStartTime).TotalMinutes -gt $constants.WaitInMinutes)
        {
            Write-Verbose ("Error occurred while exporting $($dbExporting.DatabaseName). Deleting the database copy named $($dbExporting.DatabaseCopyName).") -Verbose
            # The export id one, set the state to ToDrop either because it failed.
            $dbExporting.DatabaseState = $constants.ToDrop;
        }
        elseif(-not $?)
        {
            # We failed but we haven't hit the retry limit yet so increment RetryCount
            Write-Verbose ("Retrying with database $($dbExporting.DatabaseName)") -Verbose
            $dbExporting.RetryCount++;
        }
    }

    # Drops $dbToDrop.
    function DropDatabase($dbToDrop, $constants)
    {       
        Write-Verbose ("Database Name: $($dbToDrop.DatabaseName) State: $($dbToDrop.DatabaseState) Retry Count: $($dbToDrop.RetryCount)") -Verbose
        # Start the delete
        Remove-AzureSqlDatabase -ServerName $dbToDrop.ServerName -DatabaseName $dbToDrop.DatabaseCopyName -Force;
        # Set the state to Finished so it gets removed from the array.
        $dbToDrop.DatabaseState = $constants.Finished;
        Write-Verbose ("$($dbToDrop.DatabaseCopyName) dropped") -Verbose
    }

    # Clears all of the entries of $dbs. Needed because you can't call Clear() inside of a Workflow, it needs to be done from a function.
    function ClearDatabases($dbs)
    {
        $dbs.Clear();
    }

    AutomationAuthentication

    $serverCredentialsDictionary = 
    @{
        'SAMPLESERVER1'='NAMEOFSERVERCREDENTIAL1';
    }

    for($currentRun = 0; $currentRun -lt ([math]::Ceiling($databaseServerPairs.Length/$batchingLimit)); $currentRun++)
    {
        # We use an InlineScript here to allow the script to assign to an index of an array inside of a powershell workflow.
        [System.Collections.Generic.List[System.Object]]$dbs = InlineScript
        {
            $currentIndex = $USING:batchingLimit * $USING:currentRun;
            $tempDatabaseServerPairs = $USING:databaseServerPairs
            $arraySize = $tempDatabaseServerPairs.Count - $currentIndex
            if($arraySize -gt $USING:batchingLimit)
            {
                $arraySize = $USING:batchingLimit
            }

            [System.Collections.Generic.List[System.Object]]$tempDbs = New-Object System.Collections.Generic.List[System.Object]
            # Loop through all the databses in the $databaseServerPairs array and add corresponding database objects into the array.
            for($currentIndex; $currentIndex -lt $tempDatabaseServerPairs.Length -and $currentIndex -lt ($USING:currentRun*$USING:batchingLimit + $USING:batchingLimit); $currentIndex++)
            {
                # Create the new object.
                $dbObj = New-Object System.Object;
                # Add the DatabaseName property and set it.
                $dbObj | Add-Member -type NoteProperty -name DatabaseName -Value $tempDatabaseServerPairs[$currentIndex].DatabaseName;
                # Add a unique time at the end of DatabaseCopyName so that we have a unique database name every time. 
                $currentTime = Get-Date -format "_yyyy-MM-dd_HH:mm.ss";
                $dbCopyName = $tempDatabaseServerPairs[$currentIndex].DatabaseName + $currentTime;
                # Add the DatabaseCopyName property and set it.
                $dbObj | Add-Member -type NoteProperty -name DatabaseCopyName -Value $dbCopyName;
                # Add the ServerName property and set it.
                $dbObj | Add-Member -type NoteProperty -name ServerName -Value $tempDatabaseServerPairs[$currentIndex].ServerName;
                # Add the Export property and set it to $null for now. This will be used to look up the export after it has been started.
                $dbObj | Add-Member -type NoteProperty -name Export -Value $null;
                # Add the DatabaseState property and set it to ToCopy so that the "state machine" knows to start the copy of the database.
                $dbObj | Add-Member -type NoteProperty -name DatabaseState -Value 0;
                # Add the RetryCount property and set it to 0. This will be used to count the number of time we retry each failable operation.
                $dbObj | Add-Member -type NoteProperty -name RetryCount -Value 0;
                # Add the OperationStartTime property and set it to $null for now. This will be used when an operation starts to correcly do timeouts.
                $dbObj | Add-Member -type NoteProperty -name OperationStartTime -Value $null;
                $tempDbs.Add($dbObj)
            }
            return $tempDbs
        }

        # The variable containing all of the state, the retry limit, and the wait in minutes variables.
        $constants = InlineScript
        {
            $constants = New-Object System.Object;
            $constants | Add-Member -type NoteProperty -name ToCopy -Value 0
            $constants | Add-Member -type NoteProperty -name Copying -Value 1
            $constants | Add-Member -type NoteProperty -name ToExport -Value 2
            $constants | Add-Member -type NoteProperty -name Exporting -Value 3
            $constants | Add-Member -type NoteProperty -name ToDrop -Value 4
            $constants | Add-Member -type NoteProperty -name Finished -Value 5
            $constants | Add-Member -type NoteProperty -name RetryLimit -Value 5
            $constants | Add-Member -type NoteProperty -name WaitInMinutes -Value 4320

            return $constants
        }

        # Continually call ExportProcess until all of the database objects have been removed from the array.
        while($dbs.Count -gt 0)
        {
            # Get all database objects in the ToCopy state and start the database copy.
            $dbsToCopy = $dbs | Where-Object DatabaseState -eq $constants.ToCopy;
            Write-Verbose "dbsToCopy: $(([array]$dbsToCopy).Count)" -Verbose
            for($i = 0; $i -lt ([array]$dbsToCopy).Count; $i++)
            {
                CopyDatabase $dbsToCopy[$i] $constants

                Checkpoint-Workflow

                AutomationAuthentication
            }
        
            # Get all database objects in the Copying state and check on their copy progress.
            $dbsCopying = $dbs | Where-Object DatabaseState -eq $constants.Copying;
            Write-Verbose "dbsCopying: $(([array]$dbsCopying).Count)" -Verbose
            for($i = 0; $i -lt ([array]$dbsCopying).Count; $i++)
            {
                CheckCopy $dbsCopying[$i] $constants

                Checkpoint-Workflow

                AutomationAuthentication
            }
        
            # Get all database objects in the ToExport state and start their export.
            $dbsToExport = $dbs | Where-Object DatabaseState -eq $constants.ToExport;
            Write-Verbose "dbsToExport: $(([array]$dbsToExport).Count)" -Verbose
            for($i = 0; $i -lt ([array]$dbsToExport).Count; $i++)
            {
                ExportDatabase $dbsToExport[$i] $serverCredentialsDictionary[$dbsToExport[$i].ServerName] $constants
                
                Checkpoint-Workflow

                AutomationAuthentication
            }
        
            # Get all database objects in the Exporting state and check on their export progress.
            $dbsExporting = $dbs | Where-Object DatabaseState -eq $constants.Exporting;
            Write-Verbose "dbsExporting: $(([array]$dbsExporting).Count)" -Verbose
            for($i = 0; $i -lt ([array]$dbsExporting).Count; $i++)
            {
                CheckExport $dbsExporting[$i] $serverCredentialsDictionary[$dbsExporting[$i].ServerName] $constants

                Checkpoint-Workflow

                AutomationAuthentication
            }
        
            # Get all database objects in the ToDrop state and start their drop.
            $dbsToDrop = $dbs | Where-Object DatabaseState -eq $constants.ToDrop;
            Write-Verbose "dbsToDrop: $(([array]$dbsToDrop).Count)" -Verbose
            for($i = 0; $i -lt ([array]$dbsToDrop).Count; $i++)
            {
                DropDatabase $dbsToDrop[$i] $constants

                Checkpoint-Workflow

                AutomationAuthentication
            }
        
            # Get all database objects in the Finished state and remove them from the array.
            $dbsFinished = $dbs | Where-Object DatabaseState -eq $constants.Finished;
            Write-Verbose "dbsFinished: $(([array]$dbsFinished).Count)" -Verbose
            if(([array]$dbsFinished).Count -eq $dbs.Count)
            {
                ClearDatabases($dbs);

                Checkpoint-Workflow

                AutomationAuthentication
            }
        }
    }
}