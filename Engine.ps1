#Documentation
<#Script Logic

1. Start Health Check to see all data is good, all connections are good, Config file is good, Credentials are good, etc. 
2. Scan Users-Time.txt, Enter Data to $Startdate and $EndDate
3. Run query against MicroDb to get the data locally between the dates
4. Create temp file with all the biometric numbers that signed in the date range, in this temp file the biometric numbers should be uniqe 
5. Start a loop:
	Foreach line(biometric number) in the file:
		Check if $line is number and not space
		Get the Data of all the dates this biometric signed in or out to $Dates
		Run a Nested loop:
			Foreach Date in $Dates :
				Count number of Sign ins in the Db $DBSignin
				Count number of Sign outs in the Db $DBSignout
				if $DBSignin < 2 (means it can be only 0 or 1) 
					$TempData will hold all the INs of the user in the same day hold it in an array
					$index=0
					for ($i == $dbins; $i < 2; $i++)
						($tempData[$index] -ne  $null)
							True: Insert Data to db and $i++
							False: Break out of this loop
				#Same logic for signouts
				if $DBSignout < 2 (means it can be only 0 or 1) 
					$TempData will hold all the outs of the user in the same day hold it in an array
					$index=0
					for ($i == $dbouts; $i < 2; $i++)
						($tempData[$index] -ne $null)
							True: Insert Data to db and $i++
							False: Break out of this loop


#>



$CfgFile='C:\ProgramData\IT-Scripts\SignIN\sign.cfg'

if ($args[0] -eq '-generate'){
	Write-host "Generating Config file ..."
	"#Config file for Sign in / out app." | out-file $CfgFile
 	Add-Content -Path $CfgFile -Value "#If for any reason there is a need for regenerating this config file run : ./engine.ps1 -generate`r`n"
	Add-Content -Path $CfgFile -Value "Data_File_Users_Sign_in_Out = C:\Path\To\Database\Users-Time.txt`r`nLog_File = C:\Path\To\LogFile\logfile.log`r`n`r`n#Users Directory should be synced with the directory inside SignIn.ps1, this is the path the users will write to when sigining in" 
	Add-Content -Path $CfgFile -Value "Users_Directory = \\Path\ToShared\Folder$`r`nSMTP_SERVER = smtp.server.local`r`nMAIL_FROM = Entername@domain.com`r`n`r`n#Database MicroTime`r`nDATABASE_SERVER = 1.2.3.4 #Enter IP"
	Add-Content -Path $CfgFile -Value "DATABASE_NAME = micro_data`r`nDATABASE_USER = localuser`r`nDATABASE_PASS = enter-password"
exit
	
}

$CfgHere = Test-Path $CfgFile
if (-Not $CfgHere) {
	write-host "CANNOT LOCATE CONFIG FILE AT $CfgFile! EXITING"
	exit
}
#Working With MicroTime Logic 1 = out 0 = in
#Get Data From Config File
		
	$DbIP = Select-String -Path $CfgFile -SimpleMatch "DATABASE_SERVER" | ForEach-Object { $_.ToString().Split(' ')[2] }
	$DbName = Select-String -Path $CfgFile -SimpleMatch "DATABASE_NAME" | ForEach-Object { $_.ToString().Split(' ')[2] }
	$DbUser = Select-String -Path $CfgFile -SimpleMatch "DATABASE_USER" | ForEach-Object { $_.ToString().Split(' ')[2] }
	$DbPass = Select-String -Path $CfgFile -SimpleMatch "DATABASE_PASS" | ForEach-Object { $_.ToString().Split(' ')[2] }
	$logfile = Select-String -Path $CfgFile -SimpleMatch "Log_File" | ForEach-Object { $_.ToString().Split(' ')[2] }
	$location = Select-String -Path $CfgFile -SimpleMatch "Users_Directory" | ForEach-Object { $_.ToString().Split(' ')[2] }
	$Db_File = Select-String -Path $CfgFile -SimpleMatch "Data_File_Users_Sign_in_Out" | ForEach-Object { $_.ToString().Split(' ')[2] }

	$from = Select-String -Path $CfgFile -SimpleMatch "MAIL_FROM" | ForEach-Object { $_.ToString().Split(' ')[2] }
	$smtp = Select-String -Path $CfgFile -SimpleMatch "SMTP_SERVER" | ForEach-Object { $_.ToString().Split(' ')[2] }
	
	$DataDir = $Db_File.SubString(0, $Db_File.LastIndexOf('\'))
	$TmpDataFile = $Db_File.SubString(0, $Db_File.LastIndexOf('\'));$TmpDataFile+='\Data.tmp'  #Used to download MicrotimeDb and Queries locally
	$UniqueBIOData = $Db_File.SubString(0, $Db_File.LastIndexOf('\'));$UniqueBIOData+='\UniqueDB.tmp' #Used to Store Unique Data For biometric numbers
#Functions
	
Function Log ([string]$Content){
    $Date = Get-Date
    Add-Content -Path $logfile -Value ("$Date : $Content") 
}


Function HealthCheck (){
	#Functions will Run Checks on the system.
	#If Function find a critical fail and cannot fix it automaticly, script will exit.
	Log "Checking Health ..."

	$Test = Test-Path $Db_File
	if (-Not $Test) {
		Log "Service is DOWN! - Cannot Find $db_file"
		exit
	}

	$DBQuery = "SELECT [Id] FROM [$dbname].[dbo].[ClockTraffic] WHERE DateRecord = '1.1.2020'"#Simple query just to test Credentials
	$DBSuccess = (DBConnection -server "$dbip" -database "$dbname" -dbuser "$dbuser" -dbpass "$dbpass" -Query $DBQuery)


	if (Test-Connection $DbIP){
		Log "Connection to DataBase server is Good"
	} else {
		$Down = $True 
		Log "Service is DOWN! - Connection to $DbIP cannot be esatblished"
		Exit}
	
	If (Test-Path $location){
		Log "Test Path $location Success"
	} else {
		Log "Service is DOWN! - Cannot find $location"
		Exit}


	if ($DBSuccess -ne $Null) {
	Log "Database User Name + Password + DB name is Good"
	} else {
	Log "Service is DOWN! - Database Server is Alive, but check Db Username + Password + Db Name"
	Exit}	

	#Check Data file for users with no biometric numbers data
	$Bad_Data = (gc $Db_File | Select-String "\bNO_BIO_DATA\b") 
	if ($Bad_Data -ne $null) {
	$Bad_Data = ($Bad_Data | Out-String).Trim()
	Log "Warning - Found users in data file $db_file with no biometric info, Please make sure Attribute editor extensionAttribute1 hold biometric info"
	Log "-----Corrupted Data Start-----"
	Log "$Bad_Data"
	Log "-----Corrupted Data End-----"
	
	Log "Attempting Fix"
	gc $Db_File | Select-String -NotMatch "\bNO_BIO_DATA" | Set-Content $DataDir\tmp.txt
	mv $DataDir\tmp.txt $Db_File -Force

	$Bad_Data = gc $Db_File | Select-String "\bNO_BIO_DATA\b"
	if ($Bad_Data -ne $null) {
	Log "Service is DOWN! - Could not Fix $db_file, Please make sure no lines containing NO_BIG_DATA in the file"
	exit
	}
	else {
	Log "Succes $db_file is fixded."
	}}
	else {
	Log "$db_file is Good."
	}
	
	if ( $EndDate -eq "" -or  $StartDate -eq "" ) {#We are actually checking if they are $null, but they will never be null they will have space in them
		Log "Service is DOWN! - Cannot retreive Start Date or End Date from $DB_File"
		Log "Make sure that $DB_File End with ONE single Empty line"
		Exit
	}
	Log "Health is good, Script Continue"
		
}


Function Get_User_Dates_From_DBFile ([int] $BioMetric_Num, [string] $Db_File){
	#Rereive all the dates in DataFile BiometricNum has signed on or off
    Return (gc $Db_File | Select-String \b$BioMetric_Num\b | Get-Unique) # | Out-String is out .Trim()
}   
#Get_User_Dates_From_DBFile 620 $Db_File


Function Get_User_Signs_Per_Date ([int] $BioMetric_Num, [String] $Date, [String] $Data_file, [int] $InOrOut) {
	#Get all INs or OUTs for user in a specific date
	Return (gc $Data_file | Select-String "$Date" | Select-String "\b$BioMetric_Num\b" | Select-String "   $InOrOut")# | Get-Unique) We removed Get-Unique becuase replicated data sets in microdb
}

#Get_User_Signs_Per_Date 620 8/23/2017 $Db_File 0
#Count_Num_Of_Signs -BiometricNum 111 -Date 11/11/2021 -Db_File $Dbfile -InOrOut 1

Function Count_Signs_For_User_For_Day ([int] $BioMetric_Num, [String] $Date, [Int] $InOrOut ){
	#Sums up INs or OUTs for a user in a specific day
	Return (Get_User_Signs_Per_Date $BioMetric_Num $Date $Db_File $InOrOut).Count + ((Get_User_Signs_Per_Date $BioMetric_Num $Date $TmpDataFile $InOrOut).Count) 
}
#Count_Signs_For_User_For_Day 620 8/23/2017 0

Function HealthCheck (){
	#Functions will Run Checks on the system.
	#If Function find a critical fail and cannot fix it automaticly, script will exit.
	Log "Checking Health ..."

	$Test = Test-Path $Db_File
	if (-Not $Test) {
		Log "Service is DOWN! - Cannot Find $db_file"
		exit
	}

	$DBQuery = "SELECT [Id] FROM [$dbname].[dbo].[ClockTraffic] WHERE DateRecord = '1.1.2020'"#Simple query just to test Credentials
	$DBSuccess = (DBConnection -server "$dbip" -database "$dbname" -dbuser "$dbuser" -dbpass "$dbpass" -Query $DBQuery)


	if (Test-Connection $DbIP){
		Log "Connection to DataBase server is Good"
	} else {
		$Down = $True 
		Log "Service is DOWN! - Connection to $DbIP cannot be esatblished"
		Exit}
	
	If (Test-Path $location){
		Log "Test Path $location Success"
	} else {
		Log "Service is DOWN! - Cannot find $location"
		Exit}


	if ($DBSuccess -ne $Null) {
	Log "Database User Name + Password + DB name is Good"
	} else {
	Log "Service is DOWN! - Database Server is Alive, but check Db Username + Password + Db Name"
	Exit}	

	#Check Data file for users with no biometric numbers data
	$Bad_Data = (gc $Db_File | Select-String "\bNO_BIO_DATA\b") 
	if ($Bad_Data -ne $null) {
	$Bad_Data = ($Bad_Data | Out-String).Trim()
	Log "Warning - Found users in data file $db_file with no biometric info, Please make sure Attribute editor extensionAttribute1 hold biometric info"
	Log "-----Corrupted Data Start-----"
	Log "$Bad_Data"
	Log "-----Corrupted Data End-----"
	
	Log "Attempting Fix"
	gc $Db_File | Select-String -NotMatch "\bNO_BIO_DATA" | Set-Content $DataDir\tmp.txt
	mv $DataDir\tmp.txt $Db_File -Force

	$Bad_Data = gc $Db_File | Select-String "\bNO_BIO_DATA\b"
	if ($Bad_Data -ne $null) {
	Log "Service is DOWN! - Could not Fix $db_file, Please make sure no lines containing NO_BIG_DATA in the file"
	exit
	}
	else {
	Log "Succes $db_file is fixded."
	}}
	else {
	Log "$db_file is Good."
	}
	
	if ( $EndDate -eq "" -or  $StartDate -eq "" ) {#We are actually checking if they are $null, but they will never be null they will have space in them
		Log "Service is DOWN! - Cannot retreive Start Date or End Date from $DB_File"
		Log "Make sure that $DB_File End with ONE single Empty line"
		Exit
	}
	Log "Health is good, Script Continue"
		
}


Function DBConnection([string]$server, [string]$Database,[string]$dbuser,[string]$dbpass,[Parameter(Mandatory=$true)] [string]$Query,[int]$QueryTimeout = 120){
	#Send Query to MSSQL DataBase.
	$connString = "Server=$server;Database=$Database;user id=$dbuser;password=$dbpass;Connect Timeout=$QueryTimeout;"
	$DataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
	$DataAdapter.SelectCommand = new-object System.Data.SqlClient.SqlCommand ($query,$connString)
	$commandBuilder = new-object System.Data.SqlClient.SqlCommandBuilder $DataAdapter
	$dt = New-Object System.Data.DataTable
	[void]$DataAdapter.fill($dt)
	Return $dt  
}

Function Pull_All_Data_From_MicroDB_Date_Range ([String]$StartDate, [String]$EndDate){
	#Get all the Data from MicroTime Db from Date Ranges so it can be proccesed locally
	DBConnection -Server $DbIP -database $DbName -dbuser $DbUser -dbpass $DbPass `
	-Query "SELECT [DateRecord], [TimeRecord], [BadgeNum], [TypeInOut] FROM [$DbName].[dbo].[ClockTraffic] WHERE DateRecord BETWEEN '$StartDate' and '$EndDate'" 
}

Function Move_Local_DBFile_To_Old (){

	$Month = ((Get-ItemProperty -Path $Db_File).LastWriteTime).Month
	$Year = ((Get-ItemProperty -Path $Db_File).LastWriteTime).Year
	$Filename = "Archive-$Month-$Year.txt"
	if (test-path $DataDir\Old_Local_DBs\$Filename) {
		$NewFilename = (Get-Random -Maximum 999).tostring() + "_$Filename"
		MV $db_file $DataDir\Old_Local_DBs\$NewFilename 
		Log "$Filename Already exists in $DataDir\Old_Local_DBs, Created Archive file named $NewFilename"
	}
	else {
		MV $db_file $DataDir\Old_Local_DBs\$Filename 
		Log "Created Archive file named $Filename"
			
	}
}

Function Insert_Data_To_MicroDB ([String] $Data){
	#Date is passed as mm/dd/yyyy but it is saved at database as yyyy-mm-dd automaticly
	#We Pass Event_time the same as The current local date until we figure out what exactly it means 
	#Parameter Data will look like this:
	#For in: 8/23/2017 08:58:12 Shahar.Weiss 620 0
	#For Out: 8/23/2017 18:58:12 Shahar.Weiss 620 1
	$Date=$Data.Split(' ')[0]
	$Time=$Data.Split(' ')[1]; $Time = $Time.SubString(0,$Time.LastIndexOf(':'))
	$Badge=$Data.Split(' ')[3]
	$TypeInOut=$Data.Split(' ')[4]
	$Event_Time = (Get-Date).tostring().Split(' ')[0]

	DBConnection -Server $DbIP -database $DbName -dbuser $DbUser -dbpass $DbPass `
	-Query "INSERT INTO [$DbName].[dbo].[ClockTraffic] (DateRecord, TimeRecord, TypeInOut, IdEmp, BadgeNum, ClockNum, ManualRec, EventId, Event_Time, Note, ProjectId, Meal) VALUES ('$Date', '$Time', '$TypeInOut', '$Badge', '$Badge', '0', '0', '0', '$Event_Time', '', '0', '0')" 
}

#$Data = "2/2/2013 02:58:12 Shahar.Weiss 333 0"
#Insert_Data_To_MicroDB $Data 

Function Get_Uniqe_Users ([string]$file){
	#Read DataBase File and Get Biometric Numbers Uniqely
	gc $file | ForEach-Object { $_.ToString().Split(' ')[3]} | Sort-Object | Get-Unique | Out-String
}



#Script Start
	
	$test = test-path $db_file #This need to run before HealthCheck as $StartDate and $EndDate depends on it
	if (-Not $test){
		Log "Service is DOWN! - Could not find $db_file, Script cannot continue"
		exit
	}

	Log "****** Running Script ******"

	$StartDate = gc $Db_File -First 1 | ForEach-Object { $_.ToString().Split(' ')[0]}
	$EndDate = gc $Db_File -Last 1 | ForEach-Object { $_.ToString().Split(' ')[0]}

	HealthCheck
	Log "Working on Dates $StartDate To $EndDate" 

	Pull_All_Data_From_MicroDB_Date_Range $StartDate $EndDate | out-file $TmpDataFile

	$Tmp=Get_Uniqe_Users $Db_File ; $tmp.Trim() | Out-File $UniqueBIOData

	$NothingToAdd=$True #Will turn false if data will be added
	foreach ($line in gc $UniqueBIOData ){

	$Dates = Get_User_Dates_From_DBFile $line $Db_File 

	$Dates = $Dates | foreach {($_ -split (' '))[0]} | Get-Unique #We are Making sure each date will appear only once in data so loop wont iterate more than once over a date


	Foreach ($Date in $Dates){
		$RefinedDate = ((($date | out-string).split(' '))[0]).Trim()
			
		$DbSignIn = (Get_User_Signs_Per_Date $line $RefinedDate $TmpDataFile 0).Count
		$DbSignOUT  = (Get_User_Signs_Per_Date $line $RefinedDate $TmpDataFile 1).Count
	
		if ($DbSignIn -lt 2){ #Logic of the program that max per day = max out per day = 2
			$DataIN = Get_User_Signs_Per_Date $line $RefinedDate $Db_File 0
			$index=0
			for ($i = $dbDbSignIn; $i -lt 2; $i++){
				if ($DataIN -ne $null){
					if ( $DataIN[$index] -ne $null ){
						$Data = ($DataIN[$index].Line).Replace('    ',' ') #We are converting "2/2/2013 02:58:12 Shahar.Weiss 333     0" to "2/2/2013 02:58:12 Shahar.Weiss 333 0" 
						Log "Writing to Microdb : $Data"
						write-host "Inserting $data"
						Insert_Data_To_MicroDB $Data 
						$NothingToAdd=$False
						$index++
					}
				}
			}
		}
		#Running same logic for Signouts
		if ($DbSignOUT -lt 2){ #Logic of the program that max per day = max out per day = 2
			$DataOUT = Get_User_Signs_Per_Date $line $RefinedDate $Db_File 1
			$index=0
			for ($i = $DbSignOUT; $i -lt 2; $i++){
				if ($DataOUT -ne $null) {
					if ( $DataOUT[$index] -ne $null ){
						$Data = ($DataOUT[$index].Line).Replace('    ',' ')
						Log "Writing to Microdb : $Data"
						write-host "Inserting $data"
						Insert_Data_To_MicroDB $Data 
						$NothingToAdd=$False
						$index++
					}
				}
			}
		}
	}
	
	}
	if ($NothingToAdd) {
		Log "No Data have been inserted to MicroTime Database"
	}
	Move_Local_DBFile_To_Old
	Log "****** Script End Call ******"
	Remove-item $TmpDataFile -Force
	Remove-item $UniqueBIOData -Force

