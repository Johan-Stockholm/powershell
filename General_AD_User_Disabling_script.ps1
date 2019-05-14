#load modules and functions
Import-Module MsOnline
Import-Module ActiveDirectory

#Configuration
$upn_file = "C:\temp\user_upn_to_disable.txt"
$logfile_path = "c:\temp\disable_user_script_log_file.log"
$disabled_ou = "OU=Disabled Accounts,DC=domainname,DC=local"


function Get-RandomCharacters($length, $characters) { 
    $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length } 
    $private:ofs="" 
    return [String]$characters[$random]
}

function Scramble-String([string]$inputString){     
    $characterArray = $inputString.ToCharArray()   
    $scrambledStringArray = $characterArray | Get-Random -Count $characterArray.Length     
    $outputString = -join $scrambledStringArray
    return $outputString 
}

function Get-RandomPasswordString()
{
    $password = Get-RandomCharacters -length 9 -characters 'abcdefghiklmnoprstuvwxyz'
    $password += Get-RandomCharacters -length 4 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
    $password += Get-RandomCharacters -length 5 -characters '1234567890'
    $password += Get-RandomCharacters -length 6 -characters '!"§$%&/()=?}][{@#*+'
    $password = Scramble-String($password)
    return $password
}




#Timing
$todays_date = date -Format "yyyy-MM-dd"
$script_start_time = Get-Date -UFormat "%Y-%m-%d %H:%M:%S"
Add-Content -value "$script_start_time : Script started." -path $logfile_path

#Load upn name for users
#$rough_upn_list = Get-Content $upn_file | Where-Object { $_.Trim() -ne '' }
$ad_upn_list = Get-Content $upn_file | Foreach {$_.Trim()}
#$ad_upn_list = foreach(Foreach {$_.TrimEnd()}
$ad_upn_list

#check if all UPNs are correct. Otherwise quit
$incorrectUPNs = @()
foreach($ad_user_upn in $ad_upn_list)
{
    $ad_user_object = Get-ADUser -Filter "UserPrincipalName -eq '$ad_user_upn'"
    If ($ad_user_object -eq $Null) 
    {
        $incorrectUPNs += $ad_user_upn
    }
}
if($incorrectUPNs.Count -gt 0)
{
    Write-Output "$datetime_now : The follow UPN in input list could not be found. Please correct:"
    foreach($bad_upn in $incorrectUPNs)
    {
        Write-Output $bad_upn
    }
    Write-Output "$datetime_now : Quitting"
    break
}

#start O365 login
$UserCredential = Get-Credential
If (-Not $UserCredential) 
{
    Write-Output "$datetime_now : Incorrect credentials. Quitting"
    break
}
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $UserCredential -Authentication Basic -AllowRedirection

Import-PSSession $Session

#Set user´s mailbox type as Shared and hide from Global Address List
foreach($ad_user_upn in $ad_upn_list)
{
    Set-Mailbox -Identity $ad_user_upn -Type Shared
    $datetime_now = Get-Date -UFormat "%Y-%m-%d %H:%M:%S"
    Write-Output "$datetime_now : Mailbox: $ad_user_upn converted to Shared"
    add-content -value "$datetime_now : Mailbox: $ad_user_upn converted to Shared" -path $logfile_path

    Write-Output "$datetime_now : Mailbox: $ad_user_upn hidden from Global Address List"
    add-content -value "$datetime_now : Mailbox: $ad_user_upn hidden from Global Address List" -path $logfile_path        

    $ad_user_object = Get-ADUser -Filter { UserPrincipalName -Eq $ad_user_upn }
    Set-ADUser -Identity $ad_user_object -Replace @{msExchHideFromAddressLists=$true}
    Start-Sleep -s 2
} 



#Remove O365 licenses set directly on user in O365 rather than through security groups
Connect-MsolService -Credential $UserCredential 
foreach($ad_user_upn in $ad_upn_list)
{
    $user_licenses = (Get-MsolUser -UserPrincipalName $ad_user_upn).Licenses.AccountSkuId
    Set-MsolUserLicense -UserPrincipalName $ad_user_upn -RemoveLicenses $user_licenses
    $datetime_now = Get-Date -UFormat "%Y-%m-%d %H:%M:%S"
    Write-Output "$datetime_now : Licenses removed for $ad_user_upn. It had previously $user_licenses"
    add-content -value "$datetime_now : Licenses removed for $ad_user_upn. It had previously $user_licenses" -path $logfile_path
    Start-Sleep -s 2
} 


#Set user password to random string. Remove all AD Groups from user. Disable user and move user object to Disabled Accounts OU
foreach($ad_user_upn in $ad_upn_list)
{
    $datetime_now = Get-Date -UFormat "%Y-%m-%d %H:%M:%S"
    $ad_user_object = Get-ADUser -Filter { UserPrincipalName -Eq $ad_user_upn }

    Write-Output "$datetime_now : Setting random password for user $ad_user_upn."
    add-content -value "$datetime_now : Setting random password for user $ad_user_upn." -path $logfile_path
    $random_password = Get-RandomPasswordString
    Set-ADAccountPassword -Identity $ad_user_object -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $random_password -Force)

    Write-Output "$datetime_now : Removing all security groups for user $ad_user_upn."
    add-content -value "$datetime_now : Removing all security groups for user $ad_user_upn." -path $logfile_path
    $ADgroups = Get-ADPrincipalGroupMembership -Identity $ad_user_object | where {$_.Name -ne "Domain Users"}
	    if ($ADgroups -ne $null){
		    Remove-ADPrincipalGroupMembership -Identity $ad_user_object -MemberOf $ADgroups -Confirm:$false
	    }

    #home folder deletion requires correct access rights on home folder drive for user account executing this script
    if ($ad_user_object.HomeDirectory -ne $null) 
    {
        Write-Output "$datetime_now : Deleting home folder for user $ad_user_upn."
        add-content -value "$datetime_now : Deleting home folder for user $ad_user_upn." -path $logfile_path
        if(Test-Path $ad_user_object.HomeDirectory -PathType Container -And Test-Permission -Permission 'Delete' -Path $ad_user_object.HomeDirectory)
        {
            Remove-Item -Path $ad_user_object.HomeDirectory -Force -Recurse
            Set-ADUser -Identity $ad_user_object -HomeDrive $null -HomeDirectory $null
        }
        
    }
    
    Write-Output "$datetime_now : Disabling user account $ad_user_upn."
    add-content -value "$datetime_now : Disabling user account $ad_user_upn." -path $logfile_path
    #Set-ADUser -Identity $ad_user_object -Description "$($ad_user_object.Description) Disabled: $todays_date"    
    Disable-ADAccount -Identity $ad_user_object

    Write-Output "$datetime_now : Moving user object $ad_user_upn to $disabled_ou"
    add-content -value "$datetime_now : Moving user object $ad_user_upn to $disabled_ou" -path $logfile_path
    Start-Sleep -s 10
    Move-ADObject -Identity $ad_user_object -TargetPath $disabled_ou
    Start-Sleep -s 10
}

#Timing
$script_end_time = Get-Date -UFormat "%Y-%m-%d %H:%M:%S"
write-output "$script_end_time : Script ended."
Add-Content -value "$script_end_time : Script ended" -path $logfile_path
$script_run_time = NEW-TIMESPAN –Start $script_start_time –End $script_end_time
write-output "The script was running for: $script_run_time"
Add-Content -value "The script was running for: $script_run_time" -path $logfile_path

#Close Powershell session to O365
Remove-PSSession *


