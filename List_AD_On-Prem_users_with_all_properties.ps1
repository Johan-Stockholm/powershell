Import-Module ActiveDirectory

Get-ADUser -Filter * -Properties * | select City,Company,Country,Department,Description,DisplayName,Division,EmailAddress,Enabled,Fax,GivenName,mobile,MobilePhone,Name,Office,OfficePhone,Organization,POBox,PostalCode,SamAccountName,sn,State,StreetAddress,Surname,Title,UserPrincipalName | Export-Csv -Append -Path C:\temp\all-ad-user-info_2019-04-23.csv