#07/10/2021
#Run FarmProtection.ps1 to have IIS check for ip's and push the ip to the storage pool
#Run FarmProtection.ps1 -auto to run script in master mode where it checks for ip in pool and divide them to good and bad IP upon url query, then it builds Firewall template file to add to azure
#If running from auto,add as an argument the farm name: example, FarmProtectionV2.ps1 -auto asia    

#Get permission to Storage
net user <users> <pass> /EXPIRES:NEVER /PASSWORDCHG:NO /ADD /Y
WMIC USERACCOUNT WHERE "Name='<name>'" SET PasswordExpires=FALSE
cmdKey /add:<storage.file.core.windows.net> /user:<user> /pass:<pass>


[Net.ServicePointManager]::SecurityProtocol =[Net.SecurityProtocolType]::Tls12



#Definition & Setup

$Hostname = $env:computername
$Pos = $hostname.IndexOf("-")
$Farm = $hostname.Substring(0, $pos)

      
if ($null -ne $args[1]) {
   	$farm = $args[1]
    }

New-Item -Path \\<storage.file.core.windows.net>\data\$farm -ItemType Directory -ErrorAction SilentlyContinue

Set-Location -Path C:\Users\<user>\Downloads #Set working directory

$LogFile = 'Log.txt'

$Temp_IP_Location = "\\<storage.file.core.windows.net>\data\$farm\Temp_IP.txt"
$All_IP_Location = "\\<storage.file.core.windows.net>\data\$farm\All_IP.txt"
$Legit_IP_Location = "\\<storage.file.core.windows.net>\data\$farm\Legit_IP.txt"
$Bad_IP_Location = "\\<storage.file.core.windows.net>\data\$farm\Bad_IP.txt"
$FWTemplate_Location = "\\<storage.file.core.windows.net>\data\$farm\FW_Template.txt"

$Retry = 10 #Try catch will retry this many times before braking.
$Date = Get-Date

Write-Output $Null >> $Temp_IP_Location
Write-Output $Null >> $All_IP_Location
Write-Output $Null >> $Legit_IP_Location
Write-Output $Null >> $Bad_IP_Location
Write-Output $Null >> $FWTemplate_Location
Write-Output $null >> $backupfile
Write-Output $null >> $LogFile


#Functions
Function Log ([String] $Data){
    "$Date $Data" | Out-File $LogFile -Append
}

Function BuildNewIps () {
	#Getting local IP and pushing it to Temp_IP.txt in cloud
	$Null > ip.tmp
    Clear-Content ip.tmp
		for ($i=0; $i -lt 180; $i++) { #Change back to $i -lt 180 after finish
        ((Get-Website | Where-Object {($_.name -eq 'prod') -or ($_.name -eq 'webmobile')} | Get-WebRequest).clientIpAddress) >> ip.tmp
		start-sleep -Milliseconds 500
	}
    $Data = Get-Content ip.tmp | Sort-Object | Get-Unique 
	Log "*** Added : `r`n$Data"
    Remove-Item ip.tmp
	Return $Data
}

Function CleanOLDBCKP ([int] $X ) {
    #CHECK THIS FUNCTION
    #Will clean all last backup files and leave only x number of files.
    $files = (Get-ChildItem . | Where-Object {$_.name -like "bckp_*"}  )
    if ($files.count -ge $x){
        $files  | Sort-Object CreationTime | Select-Object -first $X | Remove-Item
    }
}

Function CheckIfIPIsIN ([String] $File, [String] $IP) {
    Return ($null -ne ( Get-Content $File | Select-String "\b$ip\b"))
 }



Function PushIPToCloud ([String] $File, [String] $ip){
    if (-Not (CheckIfIPIsIN $File $ip )){
        $ip | Out-File $File -Append
    } 
    else {
        write-host "$ip is already at $File file"
    }
}

function Retry-Command {
    [CmdletBinding()]
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Position=1, Mandatory=$false)]
        [int]$Maximum = 5,

        [Parameter(Position=2, Mandatory=$false)]
        [int]$Delay = 10
    )

    Begin {
        $cnt = 0
    }

    Process {
        do {
            $cnt++
            try {
                $ScriptBlock.Invoke()
                return
            } catch {
                Write-Error $_.Exception.InnerException.Message -ErrorAction Continue
                Start-Sleep -Seconds $Delay
            }
        } while ($cnt -lt $Maximum)

        # Throw an error after $Maximum unsuccessful invocations. Doesn't need
        # a condition, since the function returns upon successful invocation.
        throw 'Execution failed.'
    }
}


Function QueryIP ([String] $ip){
    $url = 'https://cleantalk.org/blacklists/'+$ip
    
	$stopLoop = $false
	$retryCount = 1
	do {
		try {
	        Invoke-WebRequest -uri $url -outfile file.html
			$stopLoop = $true
		} catch {
			if ($retryCount -gt $retry){
				log  "$ip Could not connect to remote server after 10 retries"
				$stopLoop = $true
			}
			else {
				log "$ip Attempting to connect to remote server, attempt #$retryCount, sleeping"
				Start-Sleep -Seconds 5
				$retryCount++
			}
		}
	} While ($stopLoop -eq $false)	


	if (Test-Path file.html ){
		$spamCheck = Get-Content file.html | where-Object {$_ -like '*Anti-Spam protection</th><td class="text-danger">Blacklisted*'}
        Remove-Item file.html
	}
    

	if ($null -ne $spamCheck){
        Return $True
	}
    Return $false
}

Function GetDataFromCloud ([String] $File){
    return Get-Content $File
}

Function BuildFWTemplate ([String] $Source, [String] $FW ) {
    #Output the sum of bad ip + current fw template
    if ($Fwdata){Clear-variable FWdata}
    if ($Output){Clear-variable Output}
    $Data = Get-Content $Source
    $FWData = (Get-Content $FW | Select-String -Pattern "\d{1,3}(\.\d{1,3}){3}" -AllMatches).Matches.Value 
    foreach ($line in $data){
        #Iterate each ip in the Bad ip file
        $found = $false #If the current ip already exists in the FW template, loop will break
        foreach ($ip in $FWData){
           if ($line -eq $ip){
              $found = $true;
              break;
            }
        }
        if (-not ($found)) {
            log "$line is a new malicous IP, adding to Firewall template file"
            $FWData += "`r`n$line"
        }
    }

    foreach ($line in (($FWData | Select-String -Pattern "\d{1,3}(\.\d{1,3}){3}" -AllMatches).Matches.Value)){
        #Since data in Firewall template is saved with commas, ip need to be extracted
        $Output += ",$line`r`n"
    }
    Return $Output
}

### Script logic start here
 #Clean all backup files and leave newset 5


if ($args.count -eq 0) {
    
    #Verify Service is running 
    $state = (Get-WindowsOptionalFeature -Online -FeatureName iis-requestmonitor).State
    if ($state -eq "Disabled") {
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-RequestMonitor
    }


    #All it does, is pushing to Temp file if the ip isnt there already
    log "Script was called with no arguments"
    $stoploop = $false
    $counter = 1
    do {
        try {
            $Data = BuildNewIps
            $stoploop = $true
            } 
            catch {
                if ($counter -gt $retry){
                        log "Could not retreive IP's from IIS, cannot continue Exiting after $retry attempts"
                        exit 1
                } 
                else {
                    log "Trying to get data from IIS failed, attempt number $counter, sleeping"
                    sleep 5
                    $counter++
                }
            }
    } While ($Stoploop -eq $false)


    if ($null -ne $data){
        foreach ($line in $data){
            do {
                $stoploop = $false
                $counter = 1
                try {
                    PushIPToCloud $Temp_IP_Location $line
                    $stoploop = $true
                    }
                    catch {
                        if ($counter -gt $retry){
                            log "Could not push $line to $Temp_IP_Location, Exiting after $retry attempts"
                            $stoploop = $true
                        }
                        else{
                            log "Could not push $line to $Temp_IP_Location, Attempt number $counter, sleeping"
                            sleep 5
                            $counter++
                        }
                    }
            } While ($Stoploop -eq $false)
        } 
        
    }
     else {
         log "No Data retrived from IIS, nothing to push to cloud storage."
     }
}


elseif ($args[0] -eq "-auto"){
   

    log "Script was called with -auto argument"
    $backupfile = "bckp_"+(get-date -format "dd-mm-yyyy_dd_m-s")+".txt"
    CleanOLDBCKP 5

    try {
        GetDataFromCloud $All_IP_Location | out-file Local_All_IP_Location.txt
        $Local_All_IP_Location = 'Local_All_IP_Location.txt'
        GetDataFromCloud $Legit_IP_Location | out-file Legit_IP_Location.txt
        $Local_Legit_IP_Location = 'Legit_IP_Location.txt'
        $TempData = GetDataFromCloud $Temp_IP_Location
    }catch {
        log "Error fetching data from cloud storage, exiting"
        exit 1
    }
    if ($null -ne $TempData){
        foreach ($line in $TempData){
            log "$line is being examined.."
            if (-Not (CheckIfIPIsIN $Local_All_IP_Location $line)) {
                if (-Not (CheckIfIPIsIN $Local_Legit_IP_Location $line)) {
                    #IP is new and not a legit one, A Query will be called
                    if (QueryIP $line) {
                        log "$line is malicious"
                        try {
                            PushIPToCloud $Bad_IP_Location $line
                            PushIPToCloud $All_IP_Location $line
                        }catch{
                            log "$line is malicous but could not push data to storage"
                        }
                    }
                    else {
                        try {
                            PushIPToCloud $Legit_IP_Location $line
                            PushIPToCloud $All_IP_Location $line
                        }catch {
                            log "$line is legit but could not push data to storage"
                        }
                    }
                }
                else {
                    "$line is Legit, moving on"
                }
            }
            else {
                "$Line Exists on IP pool, moving on"
            }
        }
       	
	$stopLoop = $false
	$retryCount = 1
	do {
		try {
			Remove-item $Temp_IP_Location -ErrorAction SilentlyContinue
			log "Delete $Temp_IP_Location"
			$stopLoop = $true
		} catch {
			if ($retryCount -gt $retry){
				log "Could not delete $Temp_IP_Location after 10 retries"
				$stopLoop = $true
			}
			else {
				Write-Host "Could not delete $Temp_IP_Location, attempt #$retryCount, sleeping"
				Start-Sleep -Seconds 5
				$retryCount++
			}
		}
	} While ($stopLoop -eq $false)	
                   
    }
    else {
        log "No Data to work with, exiting"
        if (Test-Path Local_All_IP_Location.txt) {remove-Item Local_All_IP_Location.txt }
        if (Test-Path Legit_IP_Location.txt) {remove-item Legit_IP_Location.txt }
        exit 1
    }
try {    
    $DataToPush = BuildFWTemplate $Bad_IP_Location $FWTemplate_Location
    $DataToPush | out-file $FWTemplate_Location
    $DataToPush | out-file $backupfile #Each time, a new file with date signature will be createde to hold the data in case network problem
}catch {
    log "Error while trying to push this data to storage : `r`n$data"
}
}

else {
    Write-host "Please run this script either with no parameters or with -auto"
}

if (Test-Path Local_All_IP_Location.txt) {remove-Item Local_All_IP_Location.txt }
if (Test-Path Legit_IP_Location.txt) {remove-item Legit_IP_Location.txt }