# Init PowerShell Gui
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$OutputLocaiton='\\ilfile01\signInUsrs$'

#In order to grey out Signin/Signout button, we create/delete small hidden file, Grey logic will based on existance of the file
#Enter path and filename, make sure user have permission to add data to the directory
$ItemDir='C:\it\test'
$ItemName='sign.txt'

#Functions
function GreySignInButton (){
    #Will return true in case SignINButton should be gray
    return (Test-path -path "$itemdir\sign.txt" -PathType Leaf)
}

function ConfirmSign() {
    #Return True if output file have been created
    return Test-Path -Path "$OutputLocaiton\$filename" -PathType Leaf
}
function signin() {
    if ( -not (Test-Path -Path "$itemdir\$itemname" -PathType Leaf)){
          New-item -Path $itemdir -Name "sign.txt" -ItemType "file"
          attrib +h "$itemdir\sign.txt"
    }
    $filename="$env:Username"
    if (Test-Path -Path "$OutputLocaiton\$filename" -PathType Leaf){Clear-Content -Path "$OutputLocaiton\$filename"}
    Add-Content -Path "$OutputLocaiton\$filename" -Value 0
    if (-not (ConfirmSign)){Write-Host "Error, Please contact manager"}

$Form.close()

}

function signout() {
    if (Test-Path -Path "$itemdir\sign.txt" -PathType Leaf){
        Remove-Item -Path "$itemdir\sign.txt" -Force -Confirm:$false
    }
    $filename="$env:Username"
    if (Test-Path -Path "$OutputLocaiton\$filename" -PathType Leaf){Clear-Content -Path "$OutputLocaiton\$filename"}
    Add-Content -Path "$OutputLocaiton\$filename" -Value 1
    if (-not (ConfirmSign)){Write-Host "Error, Please contact manager"}

    $Form.close()
}



#End of functions

#Gui
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Hi! Signing in? Signing out?'
$form.Size = New-Object System.Drawing.Size(350,200)
$Form.FormBorderStyle = 'Fixed3D'
$Form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Topmost = $true

$frm2label                        = New-Object system.Windows.Forms.Label
$frm2label.text                   = "Hello $ENV:username !"
$frm2label.AutoSize               = $true
$frm2label.width                  = 30
$frm2label.height                 = 30
$frm2label.location               = New-Object System.Drawing.Point(20,30)
$frm2label.Font                   = New-Object System.Drawing.Font('arial',10)

$Button1 = New-Object System.Windows.Forms.Button
$Button1.Location = New-Object System.Drawing.Size(35,65)
$Button1.Size = New-Object System.Drawing.Size(100,23)
$Button1.Text = "Sign In"
$Button1.Add_Click({signin})

$Button2 = New-Object System.Windows.Forms.Button
$Button2.Location = New-Object System.Drawing.Size(200,65)
$Button2.Size = New-Object System.Drawing.Size(100,23)
$Button2.Text = "Sign Out"
$Button2.Add_Click({signout})


if (GreySignInButton){$Button1.enabled = $false; $Button2.enabled = $true} else {$Button1.enabled = $true; $Button2.enabled = $false}

$Form.Controls.AddRange(@($Button1,$Button2,$frm2label))




[void]$form.showdialog()