$ad_group = Get-ADGroup -Filter {name -eq "Office 365 Enterprise E1"}
$users = Get-ADGroupMember $ad_group 
$users.count