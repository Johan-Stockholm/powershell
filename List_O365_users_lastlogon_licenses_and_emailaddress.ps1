<# 
.Synopsis 
   lastlogonstats is a PowerShell Scipt which can be used in O365 to fetch the last logon details of the user mailboxes. 
   using this script, administrator can identify idle/unused mailboxes and procced for a license reconciliation. Hence you end up saving more licenses. 
   This script produces a CSV based output file, which can be filtered and analyzed. 
              
.Future Editing 
    Script is by default equiped with 22 types of O365 SKU's. But O365 SKU's can change quite frequently. Script will mark new SKU's as unrecognized 
    license. Administrators can quickly add new SKU's to the script by editing the SKU hash table @ line number 64 starting with "$SKU =@{". 
    AssignedLicense column is seprated using a delimiter '::'. Please use Excel to format it. 
 #> 

Import-Module MsOnline 
 
$UserCredential = Get-Credential -Message "Login to O365"
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $UserCredential -Authentication Basic -AllowRedirection
Connect-MsolService -Credential $UserCredential 

Import-PSSession $Session

  
#Function 
function get-mailboxes { 
    $i=0 
    do { 
        Write-Progress -activity "fetching mailboxes..." -Status "please wait" 
        $mailboxes = get-mailbox -ResultSize Unlimited | ?{$_.DisplayName -notlike "Discovery Search Mailbox"} 
        $i++ 
    }until ($i -eq 1) 
 
    return $mailboxes 
} 
 
#Function 
function get-licenses ([String]$user) { 
    $assignedlicense = "" 
    $Tassignedlicense = "" 
    $Fassignedlicense = "" 
    $Sku = @{ 
        "DESKLESSPACK" = "Office 365 (Plan K1)" 
        "DESKLESSWOFFPACK" = "Office 365 (Plan K2)" 
        "LITEPACK" = "Office 365 (Plan P1)" 
        "EXCHANGESTANDARD" = "Office 365 Exchange Online Only" 
        "STANDARDPACK" = "Office 365 (Plan E1)" 
        "STANDARDWOFFPACK" = "Office 365 (Plan E2)" 
        "ENTERPRISEPACK" = "Office 365 (Plan E3)" 
        "ENTERPRISEPACKLRG" = "Office 365 (Plan E3)" 
        "ENTERPRISEWITHSCAL" = "Office 365 (Plan E4)" 
        "STANDARDPACK_STUDENT" = "Office 365 (Plan A1) for Students" 
        "STANDARDWOFFPACKPACK_STUDENT" = "Office 365 (Plan A2) for Students" 
        "ENTERPRISEPACK_STUDENT" = "Office 365 (Plan A3) for Students" 
        "ENTERPRISEWITHSCAL_STUDENT" = "Office 365 (Plan A4) for Students" 
        "STANDARDPACK_FACULTY" = "Office 365 (Plan A1) for Faculty" 
        "STANDARDWOFFPACKPACK_FACULTY" = "Office 365 (Plan A2) for Faculty" 
        "ENTERPRISEPACK_FACULTY" = "Office 365 (Plan A3) for Faculty" 
        "ENTERPRISEWITHSCAL_FACULTY" = "Office 365 (Plan A4) for Faculty" 
        "ENTERPRISEPACK_B_PILOT" = "Office 365 (Enterprise Preview)" 
        "STANDARD_B_PILOT" = "Office 365 (Small Business Preview)" 
        "MIDSIZEPACK" = "Office 365 Trial" 
        "NonLicensed" = "User is Not Licensed" 
        "PROJECTPROFESSIONAL" = "Project Online Professional"
        "MFA_STANDALONE" = "MFA_STANDALONE"
        "VISIOCLIENT" = "VISIOCLIENT"
        "POWER_BI_STANDARD" = "POWER_BI_STANDARD"
        "EMS" = "EMS"
        "DEFAULT_0" = "Unrecognized License" 
    } 
 
    $licenseparts = (Get-MsolUser -UserPrincipalName $user).licenses.AccountSku.SkuPartNumber 
     
    foreach($license in $licenseparts) { 
        if($Sku.Item($license)) { 
            $Tassignedlicense = $Sku.Item("$($license)") + "::" + $Tassignedlicense 
        } 
        else { 
            #Write-Warning -Message "user $($user) has an unrecognized license $license. Please update script." 
            #$Fassignedlicense = $Sku.Item("DEFAULT_0") + "::" + $Fassignedlicense 
            $Fassignedlicense = $license + "::" + $Fassignedlicense 
        } 
        $assignedlicense = $Tassignedlicense + $Fassignedlicense 
         
    } 
    return $assignedlicense 
} 
 
#Main 
$Header = "Alias,PrimarySmtpAddress,UserPrincipalName,WhenMailboxCreated,LastLogonTime,Type,FaxNumber,FirstName,LastName,DisplayName,AssignedLicense" 
$OutputFile = "LastLogonStats_$((Get-Date -uformat %Y%m%d%H%M%S).ToString()).csv" 
Out-File -FilePath $OutputFile -InputObject $Header -Encoding UTF8 -append 
 
$mailboxes = get-mailboxes 
 
Write-Host -Object "found $($mailboxes.count) mailboxes" -ForegroundColor Cyan 
 
$i=1 
$j=0 
 
foreach($mailbox in $mailboxes) { 
    if($j -eq 0) 
    { 
        $i++ 
     
        $watch = [System.Diagnostics.Stopwatch]::StartNew() 
 
        $assignedlicense = get-licenses -user $mailbox.userprincipalname 
 
        $smtp = $mailbox.primarysmtpaddress 
        $statistics = get-mailboxstatistics -identity "$smtp" 
        $lastlogon = $statistics.lastlogontime 
        if($lastlogon -eq $null) { 
            $lastlogon = "Never Logged In" 
        } 
        $alias = $mailbox.alias 
        $upn = $mailbox.userprincipalname 
        $whencreated = $mailbox.whenmailboxcreated 
        $type = $mailbox.recipienttypedetails 
        $FAX = (Get-User $upn).Fax 
        $FirstName = (Get-User $upn).FirstName 
        $LastName = (Get-User $upn).LastName 
        $DisplayName = (Get-User $upn).DisplayName 
 
        $watch.Stop() 
 
        $seconds = $watch.elapsed.totalseconds.tostring() 
        $remainingseconds = ($mailboxes.Count-1)*$seconds 
         
        $j++ 
    } 
    else 
    { 
        Write-Progress -activity "processing $mailbox" -status "$i Out Of $($mailboxes.Count) completed" -percentcomplete ($i / $($mailboxes.Count)*100) -secondsremaining $remainingseconds 
        $i++ 
        $remainingseconds = ($mailboxes.Count-$i)*$seconds 
 
        $assignedlicense = get-licenses -user $mailbox.userprincipalname 
 
        $smtp = $mailbox.primarysmtpaddress 
        $statistics = get-mailboxstatistics -identity "$smtp" 
        $lastlogon = $statistics.lastlogontime 
        if($lastlogon -eq $null) { 
            $lastlogon = "Never Logged In" 
        } 
        $alias = $mailbox.alias 
        $upn = $mailbox.userprincipalname 
        $whencreated = $mailbox.whenmailboxcreated 
        $type = $mailbox.recipienttypedetails 
        $FAX = (Get-User $upn).Fax 
        $FirstName = (Get-User $upn).FirstName 
        $LastName = (Get-User $upn).LastName 
        $DisplayName = (Get-User $upn ).DisplayName 
    } 
    $Data = ("$alias" + "," + $smtp + "," + $upn + "," + $whencreated + "," + $lastlogon + "," + $type + "," + $FAX + "," + $FirstName + "," + $LastName + "," + $DisplayName + "," + $assignedlicense) 
    Out-File -FilePath $OutputFile -InputObject $Data -Encoding UTF8 -append 
}