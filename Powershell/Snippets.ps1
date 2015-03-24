# vim:ts=4
<#

These snippets are for examination and discussion.

#>

	####
	# Connectivity check
	####

	if (-not (Test-Connection -Quiet $target -Count 1)) {
		&failover "Host $target cannot be reached on the network."
	}


	####
	# Set up a persistent connection (after basic check) for later use
	####

	if (-not ( $sess = New-PSSession $target )) {
		exitNG "Failed to get remote session to $target...exiting."
	}


	####
	# Service SVC running check
	####

	if (-not (Get-Service -Computer $target | Where-Object { $_.Name -eq "SVC" -and  $_.Status -eq "Running" })) {
		&failover "SVC service is not running on child $target."
	}


	####
	# Remote machine environment variable "COMPUTERNAME"
	####
	if (-not ( $baseDir = Invoke-Command $sess { $env:COMPUTERNAME } )) {
		exitNG "Windows child SVC application not found on $target...exiting."
	}
	Write-Debug "BaseDir: $baseDir"


	####
	# Get the last modification timestamp of a remote file $remoteFile
	####
	# Zulu time
	$remotefileLastModifiedZulu = Invoke-Command $sess `
							-Command {param($path) (dir $path).lastwritetime } `
							-ArgumentList "$remoteFile" `
							| Get-Date -UF "%s"
	Write-Debug "spoolfileLastModifiedZulu: $remotefileLastModifiedZulu"

# vim:ts=4

