#This script should run constantly in the background
#Infinite loop that runs every 10 seconds, search for new files in $location that should be created every time A user Sign in / out
#If files appear in the folder, this script will use the data and push it in the main Database $Db_File

#Config Part
	$CfgFile='C:\ProgramData\IT-Scripts\SignIN\sign.cfg'
	$logfile = Select-String -Path $CfgFile -SimpleMatch "Log_File" | ForEach-Object { $_.ToString().Split(' ')[2] }
	$location = Select-String -Path $CfgFile -SimpleMatch "Users_Directory" | ForEach-Object { $_.ToString().Split(' ')[2] }
	$Db_File = Select-String -Path $CfgFile -SimpleMatch "Data_File_Users_Sign_in_Out" | ForEach-Object { $_.ToString().Split(' ')[2] }
	$from = Select-String -Path $CfgFile -SimpleMatch "MAIL_FROM" | ForEach-Object { $_.ToString().Split(' ')[2] }
	$smtp = Select-String -Path $CfgFile -SimpleMatch "SMTP_SERVER" | ForEach-Object { $_.ToString().Split(' ')[2] }
	
#End of config part	

#Functions
Function Log ([string]$Content){
    $Date = Get-Date
    Add-Content -Path $logfile -Value ("$Date : $Content") }

	
Function Get_Bio ([string]$username){
	#Retreive Biometric number for user from ActiveDirectory
    Return (Get-ADUser -Identity $username -Properties extensionAttribute1).extensionAttribute1 }
 
 
Function Get_Manager_Mail ([string]$username){
	#Retreive SMTP from User's Manager
    $Manager=(Get-ADUser -Identity $username -Properties Manager).Manager
	$smtp = Get-ADUser -Identity $Manager -Properties proxyAddresses | select -ExpandProperty proxyAddresses | ? {$_ -cmatch '^SMTP'}
	Return $smtp.SubString(5)
    }
#End Functions
	
while ($true){
	$files = gci $location
    foreach ($file in $files){
    $time=((Get-ItemProperty -Path $file.fullname LastWriteTime).lastwritetime)
    $content = gc $file.FullName
	[str]$Text = "$time $file"
		if ( $text[0] -eq '0' ) {$Text=$Text.SubString(1)} #This is needed to replace 02/02/2020 with 2/02/2020 For example
    $name_bio = Get_Bio("$file")
		if ($name_bio -eq $null){
			Add-Content -Path $Db_File -Value "$Text NO_BIO_DATA    $content"#This space infront of $content is needed!
			Log "Error : $file has no biometric value in extensionAttribute1 (ActiveDirectory)" 
			}
		else {
				Add-Content -Path $Db_File -Value "$Text $name_bio    $content"
		}
		
    if ($content -eq "0"){
	#Send mail to manager
	$to = Get_Manager_Mail $file
	Send-MailMessage -From $from -To $to -Subject "$file has Signed in" -smtp $smtp
	
	}
	
	Remove-Item $file.FullName
    }
    sleep 10
}