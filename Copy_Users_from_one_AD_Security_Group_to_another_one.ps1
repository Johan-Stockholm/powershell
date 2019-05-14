$source_group = Get-ADGroupMember -Filter {name -eq "Source Group"}
$destination_group = Get-ADGroupMember -Filter {name -eq "Destination Group"}

foreach ($user in $source_group) { 
    Add-ADGroupMember -Identity $destination_group -Members $user.distinguishedname 
}