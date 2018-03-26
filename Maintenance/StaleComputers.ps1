# Moves Computers that haven't resynced their password in the past 120 days
# to an OU called 'Disabled'.. remove the 'whatif' at the end of the line to make it acutally do work

Import-Module ActiveDirectory

$d = [DateTime]::Today.AddDays(-120); Get-ADComputer -Filter  ‘PasswordLastSet -le $d’ -SearchBase “DC=your,DC=domain,DC=com”| Move-ADObject -TargetPath “OU=Disabled,DC=your,DC=domain,DC=com” -whatif